-- Ria ki Shaadi Split: database setup (tables prefixed rs_).
-- People can be added anytime; expenses point at people by id.

create table if not exists public.rs_people (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null check (char_length(btrim(name)) between 1 and 30),
  face smallint not null default 0 check (face between 0 and 11)
);

create table if not exists public.rs_expenses (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  kind text not null default 'expense' check (kind in ('expense', 'settle')),
  note text not null default 'Expense' check (char_length(note) <= 60),
  amount numeric(12,2) not null check (amount > 0 and amount < 100000000),
  payer uuid not null references public.rs_people(id) on delete restrict,
  split uuid[] not null check (array_length(split, 1) between 1 and 200)
);

create table if not exists public.rs_settings (
  id int primary key default 1 check (id = 1),
  budget numeric(12,2) not null default 0 check (budget >= 0 and budget < 1000000000)
);
insert into public.rs_settings (id) values (1) on conflict (id) do nothing;

-- Nobody can be removed while an expense includes them.
create or replace function public.rs_block_used_person_delete()
returns trigger language plpgsql set search_path = public as $$
begin
  if exists (select 1 from public.rs_expenses e where e.payer = old.id or old.id = any(e.split)) then
    raise exception 'This person is part of an expense and cannot be removed';
  end if;
  return old;
end $$;
drop trigger if exists rs_people_block_used_delete on public.rs_people;
create trigger rs_people_block_used_delete before delete on public.rs_people
  for each row execute function public.rs_block_used_person_delete();

alter table public.rs_people enable row level security;
alter table public.rs_expenses enable row level security;
alter table public.rs_settings enable row level security;

create policy "rs_people read"    on public.rs_people for select to anon, authenticated using (true);
create policy "rs_people add"     on public.rs_people for insert to anon, authenticated with check (true);
create policy "rs_people edit"    on public.rs_people for update to anon, authenticated using (true) with check (true);
create policy "rs_people remove"  on public.rs_people for delete to anon, authenticated using (true);
create policy "rs_expenses read"   on public.rs_expenses for select to anon, authenticated using (true);
create policy "rs_expenses add"    on public.rs_expenses for insert to anon, authenticated with check (true);
create policy "rs_expenses delete" on public.rs_expenses for delete to anon, authenticated using (true);
create policy "rs_settings read"   on public.rs_settings for select to anon, authenticated using (true);
create policy "rs_settings edit"   on public.rs_settings for update to anon, authenticated using (id = 1) with check (id = 1);

grant select, insert, update, delete on public.rs_people to anon, authenticated;
grant select, insert, delete on public.rs_expenses to anon, authenticated;
grant select, update on public.rs_settings to anon, authenticated;

do $$ begin alter publication supabase_realtime add table public.rs_people;   exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.rs_expenses; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.rs_settings; exception when duplicate_object then null; end $$;
