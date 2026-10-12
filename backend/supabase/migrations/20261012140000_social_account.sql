-- Connected accounts for the Content overview (owner, 2026-10-12): Instagram read through Apify, LinkedIn and X numbers
-- typed in by the owner (no official APIs). followers is null when the owner has no account there yet.

create table public.social_account (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
  platform    text not null check (platform in ('instagram', 'linkedin', 'x')),
  handle      text not null default '' check (length(handle) <= 100),
  followers   integer check (followers >= 0 and followers < 1000000000),
  rev         bigint not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (owner_id, platform)
);

alter table public.social_account enable row level security;
create policy owner_only on public.social_account for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create trigger touch before insert or update on public.social_account for each row execute function public.touch_row();
create index on public.social_account (owner_id, rev);
