-- Live website on Vercel.
update public.site_settings set site_url = 'https://bytebox-ejim.vercel.app', updated_at = now() where id = 1;
alter table public.site_settings alter column site_url set default 'https://bytebox-ejim.vercel.app';
