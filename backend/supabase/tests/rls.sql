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

-- A cannot write usage rows.
do $$ begin
  begin
    insert into public.model_usage (feature, model) values ('x', 'y');
    raise exception 'usage insert should have failed';
  exception when insufficient_privilege then null;
  end;
end $$;

-- User B sees nothing of A's and cannot write rows owned by A.
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
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
end $$;
select 'all RLS checks passed' as result;
