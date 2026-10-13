-- A third mailbox: the owner's university account (host set by secret).
alter table public.email_msg drop constraint email_msg_account_check;
alter table public.email_msg add constraint email_msg_account_check check (account in ('gmail', 'icloud', 'uni'));
alter table public.mail_state drop constraint mail_state_account_check;
alter table public.mail_state add constraint mail_state_account_check check (account in ('gmail', 'icloud', 'uni'));
