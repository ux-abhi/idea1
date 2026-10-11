-- Row-level security and action guard checks. Fails loudly on the first broken expectation.
\set ON_ERROR_STOP on
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'), ('00000000-0000-0000-0000-00000000000b');

create function pg_temp.as_user(u text) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', false);
  perform set_config('request.jwt.claim.sub', u, false);
end $$;

-- User A writes.
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
insert into public.profile default values;
insert into public.item (type, title) values ('note', 'A secret');
insert into public.action (kind, risk, payload, payload_hash, proposed_by)
  values ('send_email', 'red', '{"to":"x"}', '\x01', 'blink'),
         ('add_reminder', 'green', '{"t":"y"}', '\x02', 'blink');

do $$ begin
  assert (select count(*) from public.item) = 1, 'A should see own item';
  assert (select rev from public.item limit 1) > 0, 'revision should be stamped';
  assert (select owner_id from public.item limit 1) = auth.uid(), 'owner defaults to caller';
end $$;

-- A cannot approve a red action directly, but can approve a green one.
do $$ begin
  begin
    update public.action set status = 'approved' where risk = 'red';
    raise exception 'red approval should have failed';
  exception when raise_exception then
    if sqlerrm not like 'red actions%' then raise; end if;
  end;
  begin
    insert into public.action (kind, risk, payload, payload_hash, proposed_by, status)
      values ('send_email', 'red', '{"to":"x"}', '\x03', 'blink', 'approved');
    raise exception 'pre-approved red insert should have failed';
  exception when raise_exception then
    if sqlerrm not like 'red actions%' then raise; end if;
  end;
  update public.action set status = 'approved' where risk = 'green';
  begin
    update public.action set payload = '{"to":"evil"}' where risk = 'green';
    raise exception 'payload change should have failed';
  exception when raise_exception then
    if sqlerrm not like '%cannot change%' then raise; end if;
  end;
end $$;

-- payload_hash is computed by the server, whatever the client sends.
do $$ begin
  assert (select payload_hash from public.action where risk = 'green')
       = sha256(convert_to((select payload::text from public.action where risk = 'green'), 'UTF8')),
       'payload_hash must be sha256 of the stored payload';
end $$;

-- Approval keys: the first device may enrol once; nothing can replace, remove or add a second key.
insert into public.device (id, platform, name) values
  ('00000000-0000-0000-0000-0000000000d1', 'macos', 'Mac'),
  ('00000000-0000-0000-0000-0000000000d2', 'ios', 'Phone');
update public.device set approval_key = '\x04' || decode(repeat('ab', 64), 'hex') where id = '00000000-0000-0000-0000-0000000000d1';
do $$ begin
  begin
    update public.device set approval_key = '\x04' || decode(repeat('cd', 64), 'hex') where id = '00000000-0000-0000-0000-0000000000d1';
    raise exception 'key replace should have failed';
  exception when raise_exception then
    if sqlerrm not like '%only be enrolled once%' then raise; end if;
  end;
  begin
    update public.device set approval_key = '\x04' || decode(repeat('cd', 64), 'hex') where id = '00000000-0000-0000-0000-0000000000d2';
    raise exception 'second device key should have failed';
  exception when raise_exception then
    if sqlerrm not like '%only be enrolled once%' then raise; end if;
  end;
  begin
    update public.device set approval_key = null where id = '00000000-0000-0000-0000-0000000000d1';
    raise exception 'key removal should have failed';
  exception when raise_exception then
    if sqlerrm not like '%cannot be removed%' then raise; end if;
  end;
end $$;

-- A cannot write usage rows.
do $$ begin
  begin
    insert into public.model_usage (feature, model) values ('x', 'y');
    raise exception 'usage insert should have failed';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Habits: A logs a day once per habit; a bad status or empty name is refused.
insert into public.habit (id, name) values ('00000000-0000-0000-0000-0000000000f1', 'Read 20 pages');
insert into public.habit_log (habit_id, day, status) values ('00000000-0000-0000-0000-0000000000f1', '2026-10-12', 'done');
do $$ begin
  begin
    insert into public.habit_log (habit_id, day, status) values ('00000000-0000-0000-0000-0000000000f1', '2026-10-12', 'done');
    raise exception 'duplicate day should have failed';
  exception when unique_violation then null;
  end;
  begin
    insert into public.habit_log (habit_id, day, status) values ('00000000-0000-0000-0000-0000000000f1', '2026-10-13', 'missed');
    raise exception 'bad status should have failed';
  exception when check_violation then null;
  end;
  begin
    insert into public.habit (name, weekdays) values ('x', '{8}');
    raise exception 'bad weekday should have failed';
  exception when check_violation then null;
  end;
end $$;

-- Spaces: A makes a project space and puts the note in it; a bad status or blank title is refused.
insert into public.segment (id, title, goal) values ('00000000-0000-0000-0000-0000000000c1', 'Website', 'Launch by November');
update public.item set segment_id = '00000000-0000-0000-0000-0000000000c1';
do $$ begin
  assert (select count(*) from public.item where segment_id is not null) = 1, 'A''s note should be in the space';
  begin
    insert into public.segment (title, status) values ('x', 'someday');
    raise exception 'bad space status should have failed';
  exception when check_violation then null;
  end;
  begin
    insert into public.segment (title) values ('   ');
    raise exception 'blank space title should have failed';
  exception when check_violation then null;
  end;
end $$;

-- User B sees nothing of A's and cannot write rows owned by A.
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
do $$ begin
  assert (select count(*) from public.habit) = 0, 'B must not see A''s habits';
  assert (select count(*) from public.segment) = 0, 'B must not see A''s spaces';
  begin
    insert into public.item (type, title, segment_id) values ('task', 'sneak', '00000000-0000-0000-0000-0000000000c1');
    raise exception 'B put an item into A''s space';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.habit_log (habit_id, day, status) values ('00000000-0000-0000-0000-0000000000f1', '2026-10-14', 'done');
    raise exception 'B logged A''s habit';
  exception when insufficient_privilege then null;
  end;
end $$;
do $$ begin
  assert (select count(*) from public.item) = 0, 'B must not see A''s items';
  assert (select count(*) from public.action) = 0, 'B must not see A''s actions';
  assert (select count(*) from public.profile) = 0, 'B must not see A''s profile';
  begin
    insert into public.item (owner_id, type) values ('00000000-0000-0000-0000-00000000000a', 'note');
    raise exception 'B wrote as A';
  exception when insufficient_privilege then null;
  end;
  update public.item set title = 'hacked';
  delete from public.item;
end $$;

-- Anonymous callers see nothing.
reset role;
set role anon;
do $$ begin
  begin
    perform count(*) from public.item;
    raise exception 'anon read should have failed';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
do $$ begin
  assert (select title from public.item) = 'A secret', 'A''s data must survive B''s attempts';
  delete from public.segment;
  assert (select segment_id from public.item) is null, 'deleting a space keeps its items';
end $$;
select 'all RLS checks passed' as result;
