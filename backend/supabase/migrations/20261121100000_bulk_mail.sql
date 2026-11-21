-- Bulk Mail (2026-11-21, ADR-0003): many personal mails from one description and a contact list. A campaign holds the
-- owner's context; each recipient row holds that person's fields, the mail the AI wrote for them and where it is.
-- Nothing here sends: approved mails go to the account's Drafts folder, and sending later needs Touch ID per batch.

create table public.mail_campaign (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null default auth.uid() references auth.users on delete cascade,
  title        text not null check (length(trim(title)) between 1 and 200),
  context      text not null default '' check (length(context) <= 8000),
  goal         text not null default '' check (length(goal) <= 1000),
  tone         text not null default '' check (length(tone) <= 500),
  account      text not null check (account in ('gmail', 'icloud', 'uni')),
  status       text not null default 'draft' check (status in ('draft', 'review', 'sending', 'paused', 'done')),
  daily_limit  smallint not null default 20 check (daily_limit between 1 and 100),
  research     boolean not null default true,   -- read each company's own website for the mails (ADR-0003 §2, path A)
  -- Files that go with every mail (a portfolio deck, a few images): [{path, name, type, size}] in the files bucket.
  attachments  jsonb not null default '[]'
                 check (jsonb_typeof(attachments) = 'array' and jsonb_array_length(attachments) <= 5 and octet_length(attachments::text) <= 4000),
  segment_id   uuid references public.segment on delete set null,
  rev          bigint not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table public.mail_recipient (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null default auth.uid() references auth.users on delete cascade,
  campaign_id  uuid not null references public.mail_campaign on delete cascade,
  email        text not null check (length(email) <= 320 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  name         text not null default '' check (length(name) <= 200),
  fields       jsonb not null default '{}' check (jsonb_typeof(fields) = 'object' and octet_length(fields::text) <= 8000),
  card         jsonb not null default '{}' check (jsonb_typeof(card) = 'object' and octet_length(card::text) <= 8000),
  subject      text not null default '' check (length(subject) <= 300),
  body         text not null default '' check (length(body) <= 20000),
  flags        text[] not null default '{}' check (cardinality(flags) <= 20),
  status       text not null default 'new'
                 check (status in ('new', 'written', 'approved', 'skipped', 'in_drafts', 'sent', 'failed', 'bounced', 'replied')),
  message_id   text check (length(message_id) <= 300),
  error        text check (length(error) <= 300),
  sent_at      timestamptz,
  rev          bigint not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Never mailed in bulk: an address ("a@b.com") or a whole domain ("@b.com"), kept lowercase.
create table public.mail_do_not_contact (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
  address     text not null check (address = lower(address) and length(address) between 3 and 320 and address like '%@%'),
  created_at  timestamptz not null default now(),
  unique (owner_id, address)
);

-- What Blink read on a company's own website, one card per domain, reused for 30 days by every bulk mail. Written by
-- the mail worker only; the owner may read it.
create table public.mail_research (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
  domain      text not null check (domain = lower(domain) and length(domain) between 3 and 253),
  card        jsonb not null default '{}' check (jsonb_typeof(card) = 'object' and octet_length(card::text) <= 8000),
  fetched_at  timestamptz not null default now(),
  unique (owner_id, domain)
);

alter table public.mail_campaign enable row level security;
alter table public.mail_research enable row level security;
create policy owner_reads on public.mail_research for select to authenticated using (owner_id = (select auth.uid()));
alter table public.mail_recipient enable row level security;
alter table public.mail_do_not_contact enable row level security;
create policy owner_only on public.mail_campaign for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy owner_only on public.mail_recipient for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy owner_only on public.mail_do_not_contact for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
-- A campaign may only be linked to the owner's own Space; a recipient only added to the owner's own campaign.
create policy space_is_mine on public.mail_campaign as restrictive for all to authenticated
  with check (segment_id is null
              or exists (select 1 from public.segment s where s.id = segment_id and s.owner_id = (select auth.uid())));
create policy campaign_is_mine on public.mail_recipient as restrictive for all to authenticated
  with check (exists (select 1 from public.mail_campaign c where c.id = campaign_id and c.owner_id = (select auth.uid())));

create trigger touch before insert or update on public.mail_campaign for each row execute function public.touch_row();
create trigger touch before insert or update on public.mail_recipient for each row execute function public.touch_row();
create index on public.mail_campaign (owner_id, rev);
create index on public.mail_recipient (owner_id, rev);
-- One row per person per campaign, however the address is capitalised.
create unique index on public.mail_recipient (campaign_id, lower(email));
create index on public.mail_recipient (owner_id, lower(email));

-- The owner's files (bulk mail attachments, files in Spaces): private, each owner only in their own folder
-- (<owner id>/<campaign or space id>/<file>), 10 MB a file, documents and pictures only.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('files', 'files', false, 10485760, array['application/pdf', 'image/jpeg', 'image/png', 'image/gif', 'image/webp',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict (id) do nothing;
create policy files_own_folder on storage.objects for all to authenticated
  using (bucket_id = 'files' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'files' and (storage.foldername(name))[1] = (select auth.uid())::text);
