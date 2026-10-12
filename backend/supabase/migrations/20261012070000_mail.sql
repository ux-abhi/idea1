-- Email, Phase 5 (ARCHITECTURE §9.6, §16 email_msg): what the mail worker found, triaged; bodies are fetched on demand
-- from the mailbox and never stored (§22 data minimisation). Written by the worker (service role), read and updated
-- (status) by the owner's apps.

create table public.email_msg (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default auth.uid() references auth.users on delete cascade,
  account       text not null check (account in ('gmail', 'icloud')),
  uidvalidity   bigint not null,
  uid           bigint not null,
  message_id    text not null default '' check (length(message_id) <= 998),
  from_name     text not null default '' check (length(from_name) <= 300),
  from_addr     text not null default '' check (length(from_addr) <= 320),
  to_addr       text not null default '' check (length(to_addr) <= 320),
  subject       text not null default '' check (length(subject) <= 998),
  received_at   timestamptz,
  triage        text not null default 'normal' check (triage in ('important', 'normal', 'newsletter')),
  reason        text not null default '' check (length(reason) <= 300),    -- why it's important, in a few words
  summary       text not null default '' check (length(summary) <= 600),
  needs_reply   boolean not null default false,
  status        text not null default 'new' check (status in ('new', 'seen', 'drafted', 'done')),
  drafted_at    timestamptz,
  rev           bigint not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (owner_id, account, uidvalidity, uid)
);

-- Where the worker left off in each mailbox.
create table public.mail_state (
  owner_id        uuid not null default auth.uid() references auth.users on delete cascade,
  account         text not null check (account in ('gmail', 'icloud')),
  uidvalidity     bigint not null default 0,
  last_uid        bigint not null default 0,
  last_checked_at timestamptz,
  last_error      text check (length(last_error) <= 300),
  rev             bigint not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (owner_id, account)
);

do $$
declare t text;
begin
  foreach t in array array['email_msg', 'mail_state'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy owner_only on public.%I for all to authenticated
                    using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()))', t);
    execute format('create trigger touch before insert or update on public.%I for each row execute function public.touch_row()', t);
    execute format('create index on public.%I (owner_id, rev)', t);
  end loop;
end $$;

create index on public.email_msg (owner_id, received_at desc);

-- The apps only read mail and change its status; the worker (service role) writes everything else.
revoke insert, delete on public.email_msg from authenticated;
revoke update on public.email_msg from authenticated;
grant update (status) on public.email_msg to authenticated;
revoke insert, update, delete on public.mail_state from authenticated;
