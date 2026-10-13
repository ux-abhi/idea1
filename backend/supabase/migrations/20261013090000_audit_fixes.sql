-- Audit fixes (2026-10-13).

-- 1. Cards the owner ignored stay 'pending' after they expire (nothing marks them expired); remove them too, 180 days
--    after they expired. Cards with no expiry and approved ones (e.g. a scheduled send) are still never removed.
create or replace function public.remove_old_rows() returns jsonb
language plpgsql set search_path = '' as $$
declare mail int; actions int; events int; usage int;
begin
  delete from public.email_msg
   where (status = 'done' or triage = 'newsletter') and created_at < now() - interval '30 days'
      or created_at < now() - interval '90 days';
  get diagnostics mail = row_count;
  delete from public.action
   where status in ('done', 'undone', 'expired', 'declined', 'failed') and created_at < now() - interval '180 days'
      or status = 'pending' and expires_at < now() - interval '180 days';
  get diagnostics actions = row_count;
  delete from public.blink_event where at < now() - interval '30 days';
  get diagnostics events = row_count;
  delete from public.model_usage where at < now() - interval '400 days';
  get diagnostics usage = row_count;
  return jsonb_build_object('mail', mail, 'actions', actions, 'events', events, 'usage', usage);
end $$;
revoke all on function public.remove_old_rows() from public, anon, authenticated;

-- 2. The spend cap reads the last 24 hours of usage on every AI call; index it by time.
create index if not exists model_usage_owner_at on public.model_usage (owner_id, at);

-- 3. Account names are matched without case ("paid with n26"), so they must be unique without case too.
alter table public.money_account drop constraint money_account_owner_id_name_key;
create unique index money_account_owner_name on public.money_account (owner_id, lower(name));

-- 4. The balance time comes from the server's clock, like a spend's created_at, so a fast or slow Mac clock can't
--    drop a spend from (or double-count it in) the balance. Any write of the balance counts, even the same number:
--    "my bank shows this now" restarts the count.
create function public.money_account_balance_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.balance_at := now();
  return new;
end $$;
create trigger balance_at before insert or update of balance on public.money_account
  for each row execute function public.money_account_balance_at();

-- 5. Making an account the default is one step, so a dropped connection can't leave no default.
--    security invoker: row-level security applies, the caller can only touch their own accounts.
create function public.set_default_account(account uuid) returns void
language sql security invoker set search_path = '' as $$
  update public.money_account set is_default = false
   where is_default and id <> account and exists (select 1 from public.money_account where id = account);
  update public.money_account set is_default = true where id = account;
$$;
revoke all on function public.set_default_account(uuid) from public, anon;
grant execute on function public.set_default_account(uuid) to authenticated;
