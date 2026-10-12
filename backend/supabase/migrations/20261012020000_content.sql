-- Content engine, first slice (ARCHITECTURE §36.4): drafts per platform and the owner's voice.
-- Publishing is copy & open for now, so no tokens, media or approval hashes yet.

create table public.content_piece (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null default auth.uid() references auth.users on delete cascade,
  -- Drafts made from the same idea share it, so the app can group them.
  idea         text not null check (length(trim(idea)) between 1 and 2000),
  platform     text not null check (platform in ('instagram', 'linkedin', 'x')),
  format       text not null check (format in ('caption', 'carousel', 'reel_script', 'post', 'thread')),
  hook         text not null default '' check (length(hook) <= 500),
  body         text not null default '' check (length(body) <= 10000),
  -- Carousel slides, thread posts or reel shots, in order.
  parts        text[] not null default '{}' check (cardinality(parts) <= 30),
  hashtags     text[] not null default '{}' check (cardinality(hashtags) <= 30),
  status       text not null default 'drafted' check (status in ('drafted', 'approved', 'published', 'archived')),
  -- The writing check's score (0–100) when last saved; the app recomputes it as you edit.
  lint_score   smallint check (lint_score between 0 and 100),
  segment_id   uuid references public.segment on delete set null,
  published_at timestamptz,
  rev          bigint not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- How the owner writes (one row per owner for now; per-platform overrides come with the playbooks).
create table public.voice_profile (
  owner_id    uuid primary key default auth.uid() references auth.users on delete cascade,
  notes       text not null default '' check (length(notes) <= 4000),
  never_say   text[] not null default '{}' check (cardinality(never_say) <= 100),
  rev         bigint not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

do $$
declare t text;
begin
  foreach t in array array['content_piece', 'voice_profile'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy owner_only on public.%I for all to authenticated
                    using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()))', t);
    execute format('create trigger touch before insert or update on public.%I for each row execute function public.touch_row()', t);
    execute format('create index on public.%I (owner_id, rev)', t);
  end loop;
end $$;

-- A piece may only join the owner's own space.
create policy segment_is_mine on public.content_piece as restrictive for all to authenticated
  with check (segment_id is null
              or exists (select 1 from public.segment s where s.id = segment_id and s.owner_id = (select auth.uid())));
