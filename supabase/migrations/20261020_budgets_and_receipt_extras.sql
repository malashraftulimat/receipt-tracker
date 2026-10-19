-- ============================================================================
--  Budgets, payment deadlines, points and reduced-rate item totals
--  Safe to run on an existing project (idempotent).
-- ============================================================================

alter table public.receipts
  add column if not exists tax_8_items_total  integer,
  add column if not exists tax_10_items_total integer,
  add column if not exists due_date           timestamptz,
  add column if not exists reminder_at        timestamptz,
  add column if not exists point_brand        text,
  add column if not exists point_amount       integer;

create index if not exists receipts_due_date_idx
  on public.receipts (user_id, due_date)
  where due_date is not null;

create table if not exists public.budgets (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  month          timestamptz not null,
  salary         integer not null default 0,
  savings_goal   integer not null default 0,
  fixed_expenses integer not null default 0,
  note           text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (user_id, month)
);

alter table public.budgets enable row level security;

drop policy if exists budgets_owner_all on public.budgets;
create policy budgets_owner_all on public.budgets
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop trigger if exists budgets_touch_updated_at on public.budgets;
create trigger budgets_touch_updated_at
  before update on public.budgets
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- 1c. Itemized receipt lines
-- ---------------------------------------------------------------------------

create table if not exists public.receipt_items (
  id          uuid primary key default gen_random_uuid(),
  receipt_id  uuid not null references public.receipts (id) on delete cascade,
  name        text not null,
  quantity    integer not null default 1,
  unit_price  integer,
  total_price integer not null default 0,
  tax_rate    integer check (tax_rate in (8, 10) or tax_rate is null),
  category_id uuid references public.categories (id) on delete set null,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now()
);

create index if not exists receipt_items_receipt_idx
  on public.receipt_items (receipt_id, sort_order);

drop policy if exists receipt_items_owner_all on public.receipt_items;
create policy receipt_items_owner_all on public.receipt_items
  for all using (
    exists (
      select 1 from public.receipts r
      where r.id = receipt_id and r.user_id = auth.uid()
    )
  ) with check (
    exists (
      select 1 from public.receipts r
      where r.id = receipt_id and r.user_id = auth.uid()
    )
  );
