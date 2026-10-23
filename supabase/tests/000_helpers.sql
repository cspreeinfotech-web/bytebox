-- Test helpers (loaded before every test file). Plain SQL + DO/ASSERT so the
-- same files run locally and in CI with only psql.
create schema if not exists tests;

create or replace function tests.new_user(p_email text default null, p_anonymous boolean default false)
returns uuid
language plpgsql
as $$
declare v uuid := gen_random_uuid();
begin
  insert into auth.users (id, email, is_anonymous) values (v, p_email, p_anonymous);
  return v;
end;
$$;

-- Switch the JWT identity; the caller then runs `set role authenticated`.
create or replace function tests.login(p_uid uuid)
returns void
language sql
as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_uid, 'role', 'authenticated')::text, false);
$$;

-- Assert that a statement raises an error containing p_fragment.
create or replace function tests.throws(p_sql text, p_fragment text)
returns void
language plpgsql
as $$
begin
  execute p_sql;
  raise exception 'Expected error "%" but statement succeeded: %', p_fragment, p_sql;
exception when others then
  if sqlerrm like 'Expected error%' then raise; end if;
  if position(lower(p_fragment) in lower(sqlerrm)) = 0 then
    raise exception 'Expected error "%" but got "%"', p_fragment, sqlerrm;
  end if;
end;
$$;

grant usage on schema tests to anon, authenticated;
grant execute on all functions in schema tests to anon, authenticated;

create or replace function tests.ok(p_cond boolean, p_msg text)
returns void
language plpgsql
as $$
begin
  if p_cond is distinct from true then raise exception 'FAIL: %', p_msg; end if;
end;
$$;
grant execute on function tests.ok(boolean, text) to anon, authenticated;
