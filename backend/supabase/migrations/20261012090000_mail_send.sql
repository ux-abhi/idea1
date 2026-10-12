-- Mail, Phase 5 part 2: the owner teaches triage, and Blink sends mail after Touch ID (ARCHITECTURE §36.5).

-- The owner's own verdict on a sender ("always important" / "never important"). The worker applies it before the
-- model's guess and shows the latest ones to the model as examples. sender is an address or "@domain".
create table public.mail_sender_rule (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
  sender      text not null check (sender = lower(sender) and length(sender) between 3 and 320 and sender like '%@%'),
  verdict     text not null check (verdict in ('important', 'newsletter')),
  example     text not null default '' check (length(example) <= 300),   -- a subject, so the model sees what kind of mail
  rev         bigint not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (owner_id, sender)
);

alter table public.mail_sender_rule enable row level security;
create policy owner_only on public.mail_sender_rule for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create trigger touch before insert or update on public.mail_sender_rule for each row execute function public.touch_row();
create index on public.mail_sender_rule (owner_id, rev);

-- The owner may correct a mail's triage as well as its status.
grant update (status, triage) on public.email_msg to authenticated;

-- The Message-ID Blink gave its draft, so sending can remove that draft from the Drafts folder. Worker-written.
alter table public.email_msg add column draft_message_id text not null default '' check (length(draft_message_id) <= 998);

-- Sending mail is always red: approved only by a signed device challenge, never by a client status change.
alter table public.action add constraint mail_send_is_red check (kind <> 'mail.send' or risk = 'red');

-- One reply goes out once: a second approved send of the same message (after a lost network reply) is refused.
create unique index action_mail_send_once on public.action (owner_id, (payload->>'message_id'))
  where kind = 'mail.send' and status in ('approved', 'done');
