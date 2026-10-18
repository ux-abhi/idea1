-- Sender addresses in lowercase (2026-10-18), the form the owner's sender rules use, so teaching a sender whose
-- address has capitals ("John.Smith@Acme.com") re-sorts their mail too. The mail worker now stores them this way.
update public.email_msg set from_addr = lower(from_addr) where from_addr <> lower(from_addr);
