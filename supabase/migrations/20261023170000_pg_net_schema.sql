-- Security advisor: keep extensions out of the public schema.
-- pg_net is not relocatable, so recreate it in "extensions" (its functions stay in schema "net").
drop extension if exists pg_net;
create extension if not exists pg_net with schema extensions;
