-- Which Blink server package (database changes plus functions) this server runs, so the app can offer "Update Server"
-- after an app update (2026-10-24). Blink's installer writes it over the Management API; the owner only reads it.
create table public.server_info (
  key         text primary key check (key in ('package')),
  value       text not null check (length(value) between 1 and 200),
  updated_at  timestamptz not null default now()
);
alter table public.server_info enable row level security;
create policy owner_reads on public.server_info for select to authenticated
  using ((select public.is_server_owner()));
revoke insert, update, delete on public.server_info from authenticated, anon;
