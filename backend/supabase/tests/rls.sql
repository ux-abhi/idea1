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
insert into public.item (id, type, title) values ('00000000-0000-0000-0000-0000000000e1', 'note', 'A secret');
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

-- An action's kind can't change after it is proposed (an approved meeting can't become a mail send).
do $$ begin
  begin
    update public.action set kind = 'mail.send' where risk = 'red';
    raise exception 'kind change should have failed';
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
  begin
    delete from public.device where id = '00000000-0000-0000-0000-0000000000d1';
    raise exception 'deleting the approval device should have failed';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Revoking a device is one-way.
update public.device set revoked_at = now() where id = '00000000-0000-0000-0000-0000000000d2';
do $$ begin
  begin
    update public.device set revoked_at = null where id = '00000000-0000-0000-0000-0000000000d2';
    raise exception 'un-revoking should have failed';
  exception when raise_exception then
    if sqlerrm not like '%stays revoked%' then raise; end if;
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

-- Content: A drafts a post and sets a voice; a bad platform or status is refused.
insert into public.content_piece (idea, platform, format, body, planned_for) values ('Launch week', 'x', 'thread', 'Day 1', '2026-10-14');
-- A week plan's idea is kept as a post with status 'idea'.
insert into public.content_piece (idea, platform, format, status, planned_for) values ('Plan idea', 'linkedin', 'post', 'idea', '2026-10-15');
insert into public.voice_profile (notes, never_say, page, brief) values ('Plain, short sentences', '{delve}', '@yourname on Instagram', '# Brief');
do $$ begin
  begin
    insert into public.content_piece (idea, platform, format) values ('x', 'tiktok', 'post');
    raise exception 'bad platform should have failed';
  exception when check_violation then null;
  end;
  begin
    update public.content_piece set status = 'viral';
    raise exception 'bad content status should have failed';
  exception when check_violation then null;
  end;
end $$;

-- Page posts: A stores a post from their page; a non-Instagram URL or a bad handle is refused.
insert into public.social_post (platform, handle, url, caption, likes) values ('instagram', 'yourname', 'https://www.instagram.com/p/abc/', 'Checkout tips', 120);
do $$ begin
  begin
    insert into public.social_post (platform, handle, url) values ('instagram', 'yourname', 'https://evil.example/p/1');
    raise exception 'non-Instagram url should have failed';
  exception when check_violation then null;
  end;
  begin
    insert into public.social_post (platform, handle, url) values ('instagram', 'bad handle!', 'https://www.instagram.com/p/x/');
    raise exception 'bad handle should have failed';
  exception when check_violation then null;
  end;
end $$;

-- Mail: the worker (service role) writes messages; A can read them and change only their status.
reset role;
insert into public.email_msg (owner_id, account, uidvalidity, uid, subject, triage)
  values ('00000000-0000-0000-0000-00000000000a', 'gmail', 1, 42, 'Interview invite', 'important');
insert into public.email_msg (owner_id, account, uidvalidity, uid, subject, status)
  values ('00000000-0000-0000-0000-00000000000a', 'uni', 1, 7, 'Thesis feedback', 'done');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
do $$ begin
  assert (select count(*) from public.email_msg) = 2, 'A should see own mail, uni account included';
  update public.email_msg set status = 'done';
  assert (select count(*) from public.email_msg where status = 'done') = 2, 'A can mark mail done';
  begin
    update public.email_msg set subject = 'changed';
    raise exception 'A changed a mail subject';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.email_msg (account, uidvalidity, uid) values ('gmail', 1, 43);
    raise exception 'A inserted mail directly';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.email_msg set status = 'archived';
    raise exception 'bad mail status accepted';
  exception when check_violation then null;
  end;
  update public.email_msg set triage = 'newsletter' where subject = 'Interview invite';
  assert (select triage from public.email_msg where subject = 'Interview invite') = 'newsletter', 'A can correct triage';
  begin
    update public.email_msg set draft_message_id = 'x';
    raise exception 'A changed a draft id';
  exception when insufficient_privilege then null;
  end;
  -- Next steps are the worker's: the app can read them but not write them (a page can't plant an "event").
  assert (select actions from public.email_msg where subject = 'Interview invite') = '[]'::jsonb, 'actions default to an empty list';
  begin
    update public.email_msg set actions = '[{"kind":"event"}]';
    raise exception 'A could write mail actions';
  exception when insufficient_privilege then null;
  end;
  insert into public.mail_sender_rule (sender, verdict, example) values ('@glassdoor.com', 'newsletter', 'Jobs in Delhi');
  begin
    insert into public.mail_sender_rule (sender, verdict) values ('Boss@Example.com', 'important');
    raise exception 'a mixed-case sender was accepted';
  exception when check_violation then null;
  end;
  begin
    insert into public.action (kind, risk, payload, payload_hash, proposed_by) values ('mail.send', 'amber', '{}', '\x00', 'blink');
    raise exception 'an amber mail.send was accepted';
  exception when check_violation then null;
  end;
end $$;

-- The same reply can be approved to send only once.
reset role;
insert into public.action (owner_id, kind, risk, payload, payload_hash, proposed_by, status)
  values ('00000000-0000-0000-0000-00000000000a', 'mail.send', 'red', '{"message_id":"<r1@pexilim.com>"}', '\x00', 'blink', 'approved');
do $$ begin
  begin
    insert into public.action (owner_id, kind, risk, payload, payload_hash, proposed_by, status)
      values ('00000000-0000-0000-0000-00000000000a', 'mail.send', 'red', '{"message_id":"<r1@pexilim.com>"}', '\x00', 'blink', 'approved');
    raise exception 'the same reply was approved twice';
  exception when unique_violation then null;
  end;
end $$;

-- Money: A keeps their own spends and limits; nonsense amounts and categories are refused.
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
do $$ begin
  insert into public.transaction (amount, note, category) values (8.50, 'Lunch', 'food');
  insert into public.budget (category, monthly_limit) values ('food', 250);
  insert into public.social_account (platform, handle, followers) values ('linkedin', 'Test User', 1400);
  begin
    insert into public.social_account (platform, followers) values ('tiktok', 5);
    raise exception 'an unknown platform was accepted';
  exception when check_violation then null;
  end;
  insert into public.money_account (id, name, kind, balance, is_default)
    values ('00000000-0000-0000-0000-0000000000f1', 'Sparkasse', 'checking', 1200, true);
  insert into public.transaction (amount, note, category, account_id)
    values (23.40, 'Rewe', 'groceries', '00000000-0000-0000-0000-0000000000f1');
  begin
    insert into public.money_account (name, is_default) values ('N26', true);
    raise exception 'a second default account was accepted';
  exception when unique_violation then null;
  end;
  assert (select count(*) from public.transaction) = 2, 'A should see own spends';
  assert (select spent_since from public.money_account_now where name = 'Sparkasse') = 23.40, 'balance view adds up spends';
  -- A spend entered before the balance was set is already in the bank's number: it must not count again.
  insert into public.transaction (amount, note, category, account_id, created_at)
    values (99, 'Before the balance', 'groceries', '00000000-0000-0000-0000-0000000000f1', now() - interval '1 day');
  assert (select spent_since from public.money_account_now where name = 'Sparkasse') = 23.40, 'spends before balance_at are not counted';
  -- The balance time is the server's, whatever the app sends.
  insert into public.money_account (id, name, balance, balance_at)
    values ('00000000-0000-0000-0000-0000000000f2', 'N26', 50, now() - interval '3 days');
  assert (select balance_at from public.money_account where name = 'N26') = now(), 'balance_at comes from the server clock';
  begin
    insert into public.money_account (name) values ('sparkasse');
    raise exception 'an account name differing only in case was accepted';
  exception when unique_violation then null;
  end;
  perform public.set_default_account('00000000-0000-0000-0000-0000000000f2');
  assert (select array_agg(name) from public.money_account where is_default) = array['N26'], 'one step moves the default';
  perform public.set_default_account(gen_random_uuid());
  assert (select array_agg(name) from public.money_account where is_default) = array['N26'], 'an unknown account leaves the default alone';
  begin
    insert into public.transaction (amount, note) values (-5, 'refund?');
    raise exception 'a negative spend was accepted';
  exception when check_violation then null;
  end;
  begin
    insert into public.transaction (amount, category) values (5, 'crypto');
    raise exception 'an unknown category was accepted';
  exception when check_violation then null;
  end;
end $$;

-- Capture tokens: the owner adds and removes their own, never edits one, and B never sees A's.
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
do $$ begin
  insert into public.capture_token (name, token_hash) values ('iPhone', sha256('blk_test'::bytea));
  begin
    insert into public.capture_token (name, token_hash) values ('Short', '\x00');
    raise exception 'a token hash that is not 32 bytes was accepted';
  exception when check_violation then null;
  end;
  begin
    update public.capture_token set name = 'Changed';
    raise exception 'a capture token was editable';
  exception when insufficient_privilege then null;
  end;
  insert into public.transaction (amount, note, category, source, merchant) values (4.20, 'Coffee', 'food', 'applepay', 'Café');
end $$;

-- Retention: old handled mail goes, recent and pending things stay; apps can't run the cleanup.
reset role;
insert into public.email_msg (owner_id, account, uidvalidity, uid, subject, status, triage, created_at)
  values ('00000000-0000-0000-0000-00000000000a', 'gmail', 1, 900, 'Old and done', 'done', 'normal', now() - interval '40 days'),
         ('00000000-0000-0000-0000-00000000000a', 'gmail', 1, 901, 'Old but open', 'new', 'normal', now() - interval '40 days'),
         ('00000000-0000-0000-0000-00000000000a', 'gmail', 1, 902, 'Old newsletter', 'new', 'newsletter', now() - interval '40 days'),
         ('00000000-0000-0000-0000-00000000000a', 'gmail', 1, 903, 'Very old open', 'new', 'important', now() - interval '100 days');
insert into public.action (owner_id, kind, risk, payload, payload_hash, proposed_by, status, created_at)
  values ('00000000-0000-0000-0000-00000000000a', 'task.add', 'green', '{"title":"old pending"}', '\x00', 'blink', 'pending', now() - interval '200 days'),
         ('00000000-0000-0000-0000-00000000000a', 'task.add', 'green', '{"title":"old declined"}', '\x00', 'blink', 'declined', now() - interval '200 days'),
         ('00000000-0000-0000-0000-00000000000a', 'mail.send', 'red', '{"message_id":"<far@future>"}', '\x00', 'blink', 'approved', now() - interval '200 days'),
         ('00000000-0000-0000-0000-00000000000a', 'task.add', 'green', '{"title":"ignored and expired"}', '\x00', 'blink', 'pending', now() - interval '200 days');
update public.action set expires_at = now() - interval '190 days' where payload->>'title' = 'ignored and expired';
do $$ begin
  perform public.remove_old_rows();
  assert not exists (select 1 from public.email_msg where subject in ('Old and done', 'Old newsletter', 'Very old open')),
    'handled and newsletter mail after 30 days, any mail after 90 days, should go';
  assert exists (select 1 from public.email_msg where subject = 'Old but open'), 'open mail under 90 days stays';
  assert exists (select 1 from public.action where payload->>'title' = 'old pending'), 'pending cards are never removed';
  assert exists (select 1 from public.action where payload->>'message_id' = '<far@future>'), 'an approved (scheduled) send is never removed';
  assert not exists (select 1 from public.action where payload->>'title' = 'old declined'), 'finished cards after 180 days go';
  assert not exists (select 1 from public.action where payload->>'title' = 'ignored and expired'), 'pending cards 180 days past expiry go';
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
do $$ begin
  begin
    perform public.remove_old_rows();
    raise exception 'a signed-in app ran the cleanup';
  exception when insufficient_privilege then null;
  end;
end $$;

-- User B sees nothing of A's and cannot write rows owned by A.
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
do $$ begin
  assert (select count(*) from public.habit) = 0, 'B must not see A''s habits';
  assert (select count(*) from public.segment) = 0, 'B must not see A''s spaces';
  assert (select count(*) from public.content_piece) = 0, 'B must not see A''s drafts';
  assert (select count(*) from public.voice_profile) = 0, 'B must not see A''s voice';
  assert (select count(*) from public.social_post) = 0, 'B must not see A''s page posts';
  assert (select count(*) from public.email_msg) = 0, 'B must not see A''s mail';
  assert (select count(*) from public.mail_sender_rule) = 0, 'B must not see A''s sender rules';
  assert (select count(*) from public.transaction) = 0, 'B must not see A''s spends';
  assert (select count(*) from public.budget) = 0, 'B must not see A''s budgets';
  assert (select count(*) from public.money_account) = 0, 'B must not see A''s accounts';
  assert (select count(*) from public.capture_token) = 0, 'B must not see A''s capture tokens';
  assert (select count(*) from public.money_account_now) = 0, 'B must not see A''s balances';
  assert (select count(*) from public.social_account) = 0, 'B must not see A''s follower numbers';
  begin
    insert into public.transaction (amount, account_id) values (5, '00000000-0000-0000-0000-0000000000f1');
    raise exception 'B spent from A''s account';
  exception when insufficient_privilege then null;
  end;
  update public.voice_profile set notes = 'hacked', page = 'hacked', brief = 'hacked';
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
  begin
    insert into public.link (from_item, to_item, kind) values ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000e1', 'about');
    raise exception 'B linked A''s items';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.calendar_event (source, ext_id, occurrence_start, ends_at, snapshot_device)
      values ('apple', 'x', '2026-10-14 09:00+00', '2026-10-14 10:00+00', '00000000-0000-0000-0000-0000000000d1');
    raise exception 'B used A''s device on an event';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.action (kind, risk, payload, payload_hash, proposed_by, decided_by_device)
      values ('add_reminder', 'green', '{}', '\x00', 'blink', '00000000-0000-0000-0000-0000000000d1');
    raise exception 'B used A''s device on an action';
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
  assert (select notes from public.voice_profile) = 'Plain, short sentences', 'B must not change A''s voice';
  delete from public.segment;
  assert (select segment_id from public.item) is null, 'deleting a space keeps its items';
end $$;
-- Google (/meet): the owner reads only their own link; nobody reads the token or the sign-in states from a client;
-- a meeting invite is always red.
reset role;
insert into public.google_link (owner_id, email, token_secret)
  values ('00000000-0000-0000-0000-00000000000a', 'a@example.com', gen_random_uuid());
insert into public.google_oauth_state values ('\x01', '00000000-0000-0000-0000-00000000000a', now() + interval '10 minutes');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
do $$ begin
  assert (select count(*) from public.google_link) = 0, 'B must not see A''s Google link';
  begin
    perform public.google_token('00000000-0000-0000-0000-00000000000a');
    raise exception 'a client read the Google token';
  exception when insufficient_privilege then null;
  end;
  begin
    perform count(*) from public.google_oauth_state;
    raise exception 'a client read the Google sign-in states';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.google_link (owner_id, email, token_secret)
      values ('00000000-0000-0000-0000-00000000000b', 'b@example.com', gen_random_uuid());
    raise exception 'a client wrote a Google link';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.action (kind, risk, payload, payload_hash, proposed_by)
      values ('meet.create', 'green', '{}', '\x00', 'blink');
    raise exception 'a green meeting invite was accepted';
  exception when check_violation then null;
  end;
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
do $$ begin
  assert (select email from public.google_link) = 'a@example.com', 'A sees own Google link';
end $$;
reset role;

-- Keys added in the app: only the server's owner (someone with a profile) writes, only known names, never read back.
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');   -- B has no profile here
do $$ begin
  begin
    perform public.set_server_key('GROQ_API_KEY', 'gsk_x');
    raise exception 'a non-owner saved a key';
  exception when insufficient_privilege then null;
  end;
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
do $$ begin
  begin
    perform public.set_server_key('SUPABASE_SERVICE_ROLE_KEY', 'x');
    raise exception 'an unknown key name was accepted';
  exception when check_violation then null;
  end;
  begin
    perform * from public.server_keys();
    raise exception 'a client read the saved keys';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.google_disconnect('00000000-0000-0000-0000-00000000000a');
    raise exception 'a client called the server-only disconnect';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.server_key (name, secret_id) values ('GROQ_API_KEY', gen_random_uuid());
    raise exception 'a client wrote a key row directly';
  exception when insufficient_privilege then null;
  end;
end $$;
-- The owner saves, replaces and removes a key; the server reads it back; B sees nothing.
do $$ begin
  perform public.set_server_key('GROQ_API_KEY', ' gsk_one ');
  perform public.set_server_key('GROQ_API_KEY', 'gsk_two');
  assert (select count(*) from public.server_key) = 1, 'the owner sees one saved key name';
  -- Your own AI's settings are allowed names too.
  perform public.set_server_key('CUSTOM_AI_MODEL', 'mistral-large-latest');
  perform public.remove_server_key('CUSTOM_AI_MODEL');
  assert (select count(*) from public.server_key) = 1, 'a removed key name is gone';
end $$;
reset role;
set role service_role;
do $$ begin
  assert (select value from public.server_keys() where name = 'GROQ_API_KEY') = 'gsk_two', 'the server reads the latest value';
end $$;
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
do $$ begin
  assert (select count(*) from public.server_key) = 0, 'B must not see saved key names';
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
do $$ begin
  perform public.remove_server_key('GROQ_API_KEY');
  assert (select count(*) from public.server_key) = 0, 'removed key is gone';
end $$;
reset role;
do $$ begin
  assert (select count(*) from vault.secrets where name = 'blink-key:GROQ_API_KEY') = 0, 'its vault secret is gone too';
end $$;
set role anon;
do $$ begin
  begin
    perform public.set_server_key('GROQ_API_KEY', 'x');
    raise exception 'anon saved a key';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- One-click Google: only the server writes a Google link, whichever client made it.
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
do $$ begin
  begin
    perform public.google_connect('00000000-0000-0000-0000-00000000000a', 'a@example.com', 'tok', 'blink');
    raise exception 'a client wrote its own Google link';
  exception when insufficient_privilege then null;
  end;
  assert (select client from public.google_link) = 'own', 'links made before one-click count as the owner''s own app';
end $$;
reset role;
do $$ begin
  begin
    perform public.google_connect('00000000-0000-0000-0000-00000000000a', 'a@example.com', 'tok', 'someone-else');
    raise exception 'an unknown Google client was accepted';
  exception when invalid_parameter_value then null;
  end;
end $$;

-- Blink connector links: made only through create_mcp_token, seen and revoked only by their owner, never by anon.
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
do $$ declare code text; begin
  code := public.create_mcp_token();
  assert length(code) = 64, 'a connector code is 64 hex characters';
  assert (select count(*) from public.mcp_token) = 1, 'A sees their own connector link';
  assert (select token_hash from public.mcp_token) = encode(sha256(convert_to(code, 'UTF8')), 'hex'), 'only the hash is stored';
  begin
    insert into public.mcp_token (token_hash) values (repeat('a', 64));
    raise exception 'A wrote a connector hash directly';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
do $$ begin
  assert (select count(*) from public.mcp_token) = 0, 'B can''t see A''s connector links';
  delete from public.mcp_token;
end $$;
reset role;
do $$ begin
  assert (select count(*) from public.mcp_token) = 1, 'B couldn''t revoke A''s link';
end $$;
set role anon;
do $$ begin
  begin
    perform public.create_mcp_token();
    raise exception 'anon made a connector link';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- Space workspaces: a cover from the list and 2 to 8 board columns.
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
do $$ begin
  insert into public.segment (title) values ('Board check');
  assert (select columns from public.segment where title = 'Board check') = '["To do", "Doing", "Done"]'::jsonb, 'a Space starts with three columns';
  begin
    update public.segment set cover = 'https://evil.example/x.png' where title = 'Board check';
    raise exception 'a cover outside the list was accepted';
  exception when check_violation then null;
  end;
  begin
    update public.segment set columns = '["only one"]' where title = 'Board check';
    raise exception 'a board with one column was accepted';
  exception when check_violation then null;
  end;
end $$;
reset role;

-- Space canvas: nodes and links only in the owner's own Space; others see nothing and can't link into it.
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
do $$ begin
  insert into public.segment (id, title) values ('00000000-0000-0000-0000-0000000000d1', 'Canvas check');
  insert into public.space_node (id, segment_id, kind) values ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000d1', 'project');
  insert into public.space_node (id, segment_id, kind, ref, x, y) values ('00000000-0000-0000-0000-0000000000d3', '00000000-0000-0000-0000-0000000000d1', 'task', 'item-1', 300, 40);
  insert into public.space_edge (segment_id, from_node, to_node) values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000d3');
  assert (select count(*) from public.space_edge) = 1, 'A links two of their nodes';
  insert into public.space_node (segment_id, kind, x, y, w, h, label) values ('00000000-0000-0000-0000-0000000000d1', 'section', 500, 500, 600, 400, 'Research');
  begin
    insert into public.space_node (segment_id, kind, label) values ('00000000-0000-0000-0000-0000000000d1', 'heading', repeat('x', 201));
    raise exception 'a heading over 200 characters';
  exception when check_violation then null;
  end;
  begin
    insert into public.space_edge (segment_id, from_node, to_node) values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000d3', '00000000-0000-0000-0000-0000000000d3');
    raise exception 'a node linked to itself';
  exception when check_violation then null;
  end;
  begin
    insert into public.space_node (segment_id, kind) values ('00000000-0000-0000-0000-0000000000d1', 'project');
    raise exception 'a second project node';
  exception when unique_violation then null;
  end;
end $$;
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
do $$ begin
  assert (select count(*) from public.space_node) = 0, 'B can''t see A''s canvas';
  begin
    insert into public.space_node (segment_id, kind) values ('00000000-0000-0000-0000-0000000000d1', 'project');
    raise exception 'B put a node in someone else''s Space';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.space_edge (segment_id, from_node, to_node)
      values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000d3', '00000000-0000-0000-0000-0000000000d2');
    raise exception 'B linked A''s nodes';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- Canvas images: each owner reads and writes only their own folder of the private bucket.
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
do $$ begin
  insert into storage.objects (bucket_id, name) values ('canvas', '00000000-0000-0000-0000-00000000000a/space/one.jpg');
  begin
    insert into storage.objects (bucket_id, name) values ('canvas', '00000000-0000-0000-0000-00000000000b/space/two.jpg');
    raise exception 'A wrote into B''s folder';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
do $$ begin
  assert (select count(*) from storage.objects) = 0, 'B can''t see A''s images';
end $$;
reset role;
do $$ begin assert not (select public from storage.buckets where id = 'canvas'), 'the canvas bucket is private'; end $$;

-- Server package: the installer writes it; the owner reads it; nobody else reads it and no client writes it.
insert into public.server_info (key, value) values ('package', 'abc123');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
do $$ begin
  assert (select value from public.server_info where key = 'package') = 'abc123', 'the owner reads the server package';
  begin
    update public.server_info set value = 'x';
    raise exception 'a client changed the server package';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');   -- B has no profile here
do $$ begin
  assert (select count(*) from public.server_info) = 0, 'B must not read the server package';
end $$;
reset role;

-- A second login can't become a second owner.
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
do $$ begin
  begin
    insert into public.profile default values;
    raise exception 'a second profile should have failed';
  exception when raise_exception then
    if sqlerrm not like '%already has an owner%' then raise; end if;
  end;
end $$;
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
insert into public.profile default values on conflict (owner_id) do nothing; -- the owner's own check-in still works
reset role;

select 'all RLS checks passed' as result;
