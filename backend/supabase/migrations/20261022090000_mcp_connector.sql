-- The Blink connector (2026-10-22): Claude or ChatGPT can read the owner's day and add tasks and notes through the `mcp`
-- function, paid by the owner's own AI subscription. Each connector link carries a long random code; only its SHA-256 is
-- stored, so the database never holds a usable link. The owner makes and revokes links in Blink › Settings.
create table public.mcp_token (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default auth.uid() references auth.users on delete cascade,
  token_hash    text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  created_at    timestamptz not null default now(),
  last_used_at  timestamptz
);
alter table public.mcp_token enable row level security;
create policy owner_only on public.mcp_token for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
revoke all on public.mcp_token from anon, authenticated;
grant select, delete on public.mcp_token to authenticated;   -- see and revoke; links are made only by the function below

-- A new connector link code, returned once (the caller shows it as a URL); only its hash is kept.
create function public.create_mcp_token() returns text
language plpgsql security definer set search_path = '' as $$
declare code text;
begin
  if auth.uid() is null then raise exception 'sign in first' using errcode = '42501'; end if;
  code := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  insert into public.mcp_token (owner_id, token_hash) values (auth.uid(), encode(sha256(convert_to(code, 'UTF8')), 'hex'));
  return code;
end $$;
revoke all on function public.create_mcp_token() from public, anon;
grant execute on function public.create_mcp_token() to authenticated;
