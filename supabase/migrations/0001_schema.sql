-- Migracion inicial Finora. Ejecutar UNA sola vez por proyecto (sin IF NOT EXISTS a proposito).

-- Plantilla de tabla sincronizable: id lo genera el cliente (uuid v4).
create table public.accounts (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  type text not null check (type in ('cash','wallet','debit','credit')),
  initial_balance_cents bigint not null default 0,
  credit_limit_cents bigint,
  statement_day int check (statement_day between 1 and 31),
  payment_due_day int check (payment_due_day between 1 and 31),
  last4 text,
  color bigint not null default 0,
  is_archived boolean not null default false,
  updated_at timestamptz not null,
  deleted_at timestamptz
);

create table public.categories (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  icon text not null,
  color bigint not null,
  kind text not null check (kind in ('expense','income')),
  updated_at timestamptz not null,
  deleted_at timestamptz
);

create table public.transactions (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  account_id uuid not null references public.accounts (id) on delete cascade,
  category_id uuid not null references public.categories (id) on delete cascade,
  kind text not null check (kind in ('expense','income')),
  amount_cents bigint not null,
  note text,
  occurred_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz
);

create table public.savings_goals (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  target_cents bigint not null,
  saved_cents bigint not null default 0,
  deadline timestamptz,
  color bigint not null default 0,
  updated_at timestamptz not null,
  deleted_at timestamptz
);

create table public.user_settings (
  id uuid primary key references auth.users (id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  constraint user_settings_id_matches_user check (id = user_id),
  monthly_limit_cents bigint,
  alert_days_before_due int not null default 3,
  updated_at timestamptz not null,
  deleted_at timestamptz
);

-- RLS: cada usuario solo ve y escribe sus filas.
do $$
declare t text;
begin
  foreach t in array array['accounts','categories','transactions','savings_goals','user_settings'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy "own_rows" on public.%I for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id)', t);
    execute format('create index %I on public.%I (user_id, updated_at)', t || '_sync_idx', t);
  end loop;
end $$;
