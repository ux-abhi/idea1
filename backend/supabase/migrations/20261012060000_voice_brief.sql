-- The owner's creator brief (a content directory: story, projects, pillars, voice rules), used by drafts, ideas and the week plan.
alter table public.voice_profile
  add column brief text not null default '' check (length(brief) <= 40000);
