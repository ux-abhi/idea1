-- Audit fix (§36.5): a client could delete the device that holds the approval key, then enrol its own key and sign red
-- approvals with only a stolen session token. Clients can't delete devices; a lost device is marked revoked_at instead.
revoke delete on public.device from authenticated;
