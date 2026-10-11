-- Blink core schema: Phase 0 + 1 tables only. Later phases add their own migrations.
-- Every table is owned by one user and protected by row-level security (ARCHITECTURE §16, §36.9).

-- Sync cursor: every insert/update stamps a server-assigned revision (§17, §36.1).
-- shortcut: per-row revision, not per-field; upgrade when two devices edit the same row's different fields.
create sequence public.rev_seq;

create function public.touch_row() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.rev := nextval('public.rev_seq');
  new.updated_at := now();
  return new;
end $$;

create table public.profile (
  owner_id      uuid primary key default auth.uid() references auth.users on delete cascade,
  display_name  text,
  timezone      text not null default 'UTC',
  wake_time     time not null default '07:00',
  evening_time  time not null default '21:30',
  model_prefs   jsonb not null default '{}',
  settings      jsonb not null default '{}',
  rev           bigint not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table public.memory_fact (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
  category    text not null,
  text        text not null,
  source      text,
  confidence  real not null default 1 check (confidence between 0 and 1),
  rev         bigint not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- A paired Mac, iPhone or web client. approval_key is the Secure Enclave P-256 public key
-- that signs red-tier approvals (§36.5).
create table public.device (
  id                   uuid primary key default gen_random_uuid(),
  owner_id             uuid not null default auth.uid() references auth.users on delete cascade,
  platform             text not null check (platform in ('macos', 'ios', 'web')),
  name                 text not null,
  approval_key         bytea,
  apns_token           text,
  push_to_start_token  text,
  last_seen_at         timestamptz,
  revoked_at           timestamptz,
  rev                  bigint not null default 0,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create table public.item (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
  type        text not null check (type in ('note', 'task', 'reminder', 'milestone', 'event_ref', 'email_ref', 'idea', 'doc')),
  title       text not null default '',
  body        text not null default '',
  status      text not null default 'open' check (status in ('open', 'done', 'archived')),
  due_at      timestamptz,
  metadata    jsonb not null default '{}',
  deleted_at  timestamptz,
  rev         bigint not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.link (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
  from_item   uuid not null references public.item on delete cascade,
  to_item     uuid not null references public.item on delete cascade,
  kind        text not null check (kind in ('about', 'follow_up', 'source_of', 'belongs_to', 'with_person', 'repurposed_from')),
  rev         bigint not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (from_item, to_item, kind)
);

-- Calendar snapshot rows. Identity = external id + occurrence start + source (§36.1).
create table public.calendar_event (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null default auth.uid() references auth.users on delete cascade,
  source            text not null,
  ext_id            text not null,
  occurrence_start  timestamptz not null,
  ends_at           timestamptz not null,
  title             text not null default '',
  location          text,
  url               text,
  attendees         jsonb not null default '[]',
  is_all_day        boolean not null default false,
  is_declined       boolean not null default false,
  snapshot_device   uuid references public.device on delete set null,
  snapshot_at       timestamptz not null default now(),
  rev               bigint not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (owner_id, source, ext_id, occurrence_start)
);

-- Ask-First queue and audit log (§6). payload_hash is what a device signs for red-tier actions.
create table public.action (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid not null default auth.uid() references auth.users on delete cascade,
  kind               text not null,
  risk               text not null check (risk in ('green', 'amber', 'red')),
  payload            jsonb not null,
  payload_hash       bytea not null,
  status             text not null default 'pending' check (status in ('pending', 'approved', 'done', 'undone', 'expired', 'declined', 'failed')),
  proposed_by        text not null,
  expires_at         timestamptz,
  decided_at         timestamptz,
  decided_by_device  uuid references public.device on delete set null,
  result             jsonb,
  rev                bigint not null default 0,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- Learned auto-approvals. The executor never applies a rule to a red-tier action (§6, §36.4).
create table public.rule (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null default auth.uid() references auth.users on delete cascade,
  action_kind  text not null,
  condition    jsonb not null default '{}',
  auto         boolean not null default false,
  paused       boolean not null default false,
  rev          bigint not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table public.blink_event (
  id        bigint generated always as identity primary key,
  owner_id  uuid not null default auth.uid() references auth.users on delete cascade,
  at        timestamptz not null default now(),
  state     text not null,
  reason    text
);

create table public.model_usage (
  id             bigint generated always as identity primary key,
  owner_id       uuid not null default auth.uid() references auth.users on delete cascade,
  at             timestamptz not null default now(),
  feature        text not null,
  model          text not null,
  input_tokens   integer not null default 0,
  output_tokens  integer not null default 0,
  cost_usd       numeric(10, 6) not null default 0
);

-- Owner-only access on every table, plus the revision trigger on synced tables.
do $$
declare t text;
begin
  foreach t in array array['profile', 'memory_fact', 'device', 'item', 'link', 'calendar_event', 'action', 'rule', 'blink_event', 'model_usage'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy owner_only on public.%I for all to authenticated
                    using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()))', t);
    execute format('create index on public.%I (owner_id)', t);
  end loop;
  foreach t in array array['profile', 'memory_fact', 'device', 'item', 'link', 'calendar_event', 'action', 'rule'] loop
    execute format('create trigger touch before insert or update on public.%I for each row execute function public.touch_row()', t);
    execute format('create index on public.%I (owner_id, rev)', t);
  end loop;
end $$;

-- Usage rows are written by the server only; clients can read their own.
revoke insert, update, delete on public.model_usage from authenticated;

-- A red-tier action can only be approved through the verify-signature path (service role), never by a client update.
create function public.guard_action_update() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user = 'authenticated' and new.risk = 'red' and new.status <> old.status
     and new.status in ('approved', 'done') then
    raise exception 'red actions are approved by a signed device challenge only';
  end if;
  if new.risk <> old.risk or new.payload <> old.payload or new.payload_hash <> old.payload_hash then
    raise exception 'an action''s risk and payload cannot change after it is proposed';
  end if;
  return new;
end $$;

create trigger guard before update on public.action for each row execute function public.guard_action_update();

