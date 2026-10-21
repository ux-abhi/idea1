-- Your own AI (2026-10-22): any OpenAI-compatible service the owner adds in Settings › Connections › Advanced, by name,
-- address, model and key. Kept in Vault like the other keys; only the server's functions read them.
alter domain public.server_key_name drop constraint server_key_name_check;
alter domain public.server_key_name add constraint server_key_name_check check (value in (
  'ANTHROPIC_API_KEY', 'ANTHROPIC_WORKSPACE_ID', 'GROQ_API_KEY', 'OPENROUTER_API_KEY', 'APIFY_TOKEN',
  'CLOUDFLARE_API_TOKEN', 'CLOUDFLARE_ACCOUNT_ID',
  'GMAIL_ADDRESS', 'GMAIL_APP_PASSWORD', 'ICLOUD_ADDRESS', 'ICLOUD_APP_PASSWORD',
  'UNI_ADDRESS', 'UNI_PASSWORD', 'UNI_IMAP_HOST', 'UNI_SMTP_HOST',
  'GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'GOOGLE_DESKTOP_CLIENT_ID', 'GOOGLE_DESKTOP_CLIENT_SECRET',
  'CUSTOM_AI_NAME', 'CUSTOM_AI_URL', 'CUSTOM_AI_MODEL', 'CUSTOM_AI_KEY'));
