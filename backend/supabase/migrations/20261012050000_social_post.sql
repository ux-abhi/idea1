-- The owner's own published posts, read from their public page (Apify), for "what works" and better ideas (§36.4 feedback loop).
create table public.social_post (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
  platform    text not null check (platform in ('instagram')),
  handle      text not null check (handle ~ '^[A-Za-z0-9._]{1,30}$'),
  url         text not null check (url ~ '^https://www\.instagram\.com/'),
  kind        text not null default 'image' check (kind in ('image', 'video', 'carousel')),
  caption     text not null default '' check (length(caption) <= 5000),
  likes       integer,          -- null when the count is hidden
  comments    integer,
  views       integer,
  posted_at   timestamptz,
  fetched_at  timestamptz not null default now(),
  rev         bigint not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (owner_id, url)
);

alter table public.social_post enable row level security;
create policy owner_only on public.social_post for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create trigger touch before insert or update on public.social_post for each row execute function public.touch_row();
create index on public.social_post (owner_id, rev);
create index on public.social_post (owner_id, posted_at desc);
