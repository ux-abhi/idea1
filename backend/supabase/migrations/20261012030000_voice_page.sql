-- Voice profile, second pass: what the owner's page is about, so drafts and ideas fit it (ARCHITECTURE §36.4).
alter table public.voice_profile
  add column page     text not null default '' check (length(page) <= 500),     -- e.g. "@uxabhi on Instagram: UX tips"
  add column audience text not null default '' check (length(audience) <= 1000),
  add column topics   text not null default '' check (length(topics) <= 1000);
