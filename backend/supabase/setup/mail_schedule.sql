-- Mail schedule (Phase 5): every 5 minutes the server calls its own mail function. Run once per server in the SQL
-- editor, with <PROJECT_URL> replaced by the project's URL. Not a migration: pg_cron, pg_net and Vault exist only on a
-- real Supabase project, not in the CI test database.
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- A random shared secret, made and kept inside Vault; nobody ever types or sees it.
-- Safe to run again (the one-click setup may retry): the secret is made only if it isn't there yet.
select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'mail_cron_secret',
                           'Sent by the mail schedule to the mail function')
where not exists (select 1 from vault.secrets where name = 'mail_cron_secret');

-- Only the server itself (service role) can read it back, to check the schedule's calls.
create or replace function public.mail_cron_secret() returns text
language sql security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'mail_cron_secret'
$$;
revoke all on function public.mail_cron_secret() from public, anon, authenticated;
grant execute on function public.mail_cron_secret() to service_role;

select cron.schedule('mail-poll', '*/5 * * * *', $$
  select net.http_post(
    url := '<PROJECT_URL>/functions/v1/mail',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', public.mail_cron_secret()),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000)
$$);
