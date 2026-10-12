-- Weekly content plan (ARCHITECTURE §21 weekly_content_plan, §36.4): a draft can be planned for a day.
alter table public.content_piece add column planned_for date;
create index on public.content_piece (owner_id, planned_for) where planned_for is not null;
