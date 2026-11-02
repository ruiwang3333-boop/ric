-- Run once in your own Supabase project's SQL Editor.
begin;
create table if not exists public.personal_ledgers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null check (jsonb_typeof(data) = 'object'),
  revision bigint not null default 1,
  updated_at timestamptz not null default now()
);
alter table public.personal_ledgers enable row level security;
revoke all on public.personal_ledgers from anon;
grant select, insert, update on public.personal_ledgers to authenticated;
drop policy if exists ledger_owner_select on public.personal_ledgers;
create policy ledger_owner_select on public.personal_ledgers for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists ledger_owner_insert on public.personal_ledgers;
create policy ledger_owner_insert on public.personal_ledgers for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists ledger_owner_update on public.personal_ledgers;
create policy ledger_owner_update on public.personal_ledgers for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
-- Compare revisions atomically so another device's newer ledger is not overwritten.
create or replace function public.save_personal_ledger(p_data jsonb, p_expected bigint)
returns bigint language plpgsql security invoker set search_path = public as $$
declare next_revision bigint;
begin
  if auth.uid() is null then raise exception 'LOGIN_REQUIRED'; end if;
  insert into public.personal_ledgers(user_id, data, revision)
  values (auth.uid(), p_data, 1)
  on conflict (user_id) do update
    set data = excluded.data, revision = personal_ledgers.revision + 1, updated_at = now()
    where personal_ledgers.revision = p_expected
  returning revision into next_revision;
  if next_revision is null then raise exception 'CLOUD_CONFLICT'; end if;
  return next_revision;
end;
$$;
revoke all on function public.save_personal_ledger(jsonb, bigint) from public, anon;
grant execute on function public.save_personal_ledger(jsonb, bigint) to authenticated;
commit;
