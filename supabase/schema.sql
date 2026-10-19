-- ============================================================================
--  receipt_tracker — Supabase schema
--  Run in the Supabase SQL editor (or `supabase db push`).
-- ============================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------

create table if not exists public.categories (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  name        text not null,
  color       text not null default '#78909C',
  icon        text not null default 'category',
  is_default  boolean not null default false,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now(),
  unique (user_id, name)
);

create table if not exists public.receipts (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users (id) on delete cascade,
  merchant        text,
  purchased_at    timestamptz not null default now(),
  total_amount    integer not null default 0,     -- JPY, always integer yen
  subtotal_amount integer,
  tax_8_amount    integer,
  tax_10_amount   integer,
  tax_8_base      integer,
  tax_10_base     integer,
  tax_8_items_total  integer,          -- sum of 8% (reduced) item rows
  tax_10_items_total integer,          -- sum of 10% (standard) item rows
  due_date        timestamptz,         -- 支払期限 / 振込用紙 deadline
  reminder_at     timestamptz,         -- optional reminder
  point_brand     text,                -- dポイント / Ponta / Tポイント / 楽天
  point_amount    integer,
  barcode_id      text,                           -- JAN-13 / Code128 / invoice ref
  category_id     uuid references public.categories (id) on delete set null,
  note            text,
  image_path      text,                           -- object path in the `receipts` bucket
  source          text not null default 'manual'
                  check (source in ('barcode', 'ocr', 'manual')),
  raw_ocr_text    text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- Duplicate guard: one barcode per user.
create unique index if not exists receipts_user_barcode_uniq
  on public.receipts (user_id, barcode_id)
  where barcode_id is not null;

create index if not exists receipts_user_date_idx
  on public.receipts (user_id, purchased_at desc);

create index if not exists receipts_category_idx
  on public.receipts (category_id);

create index if not exists receipts_due_date_idx
  on public.receipts (user_id, due_date)
  where due_date is not null;

-- ---------------------------------------------------------------------------
-- 1b. Monthly budget / savings plan
-- ---------------------------------------------------------------------------

create table if not exists public.budgets (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  month          timestamptz not null,          -- first day of the month (UTC)
  salary         integer not null default 0,    -- 手取り月収
  savings_goal   integer not null default 0,    -- 毎月の貯蓄目標
  fixed_expenses integer not null default 0,    -- 家賃・光熱費・サブスク
  note           text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (user_id, month)
);

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
-- ---------------------------------------------------------------------------
-- 2. updated_at trigger
-- ---------------------------------------------------------------------------

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists receipts_touch_updated_at on public.receipts;
create trigger receipts_touch_updated_at
  before update on public.receipts
  for each row execute function public.touch_updated_at();

drop trigger if exists budgets_touch_updated_at on public.budgets;
create trigger budgets_touch_updated_at
  before update on public.budgets
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- 3. Row Level Security
-- ---------------------------------------------------------------------------

alter table public.categories enable row level security;
alter table public.receipts   enable row level security;
alter table public.budgets    enable row level security;
alter table public.receipt_items enable row level security;

drop policy if exists categories_owner_all on public.categories;
create policy categories_owner_all on public.categories
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists receipts_owner_all on public.receipts;
create policy receipts_owner_all on public.receipts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

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

drop policy if exists budgets_owner_all on public.budgets;
create policy budgets_owner_all on public.budgets
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 4. Storage bucket + policies  (private bucket, per-user folders)
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('receipts', 'receipts', false)
on conflict (id) do nothing;

drop policy if exists receipts_objects_select on storage.objects;
create policy receipts_objects_select on storage.objects
  for select using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists receipts_objects_insert on storage.objects;
create policy receipts_objects_insert on storage.objects
  for insert with check (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists receipts_objects_update on storage.objects;
create policy receipts_objects_update on storage.objects
  for update using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists receipts_objects_delete on storage.objects;
create policy receipts_objects_delete on storage.objects
  for delete using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- 5. Seed default categories for every new user
-- ---------------------------------------------------------------------------

create or replace function public.seed_default_categories(p_user uuid)
returns void
language sql
as $$
  insert into public.categories (user_id, name, color, icon, is_default, sort_order)
  values
    (p_user, '食費',       '#4CAF50', 'grocery',    true, 0),
    (p_user, '外食',       '#FF7043', 'restaurant', true, 1),
    (p_user, '日用品',     '#42A5F5', 'shopping',   true, 2),
    (p_user, '光熱費',     '#FFB300', 'bolt',       true, 3),
    (p_user, '交通費',     '#26A69A', 'train',      true, 4),
    (p_user, '娯楽',       '#AB47BC', 'games',      true, 5),
    (p_user, '医療・医薬品', '#EF5350', 'pharmacy',   true, 6),
    (p_user, 'その他',     '#78909C', 'category',   true, 7)
  on conflict (user_id, name) do nothing;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.seed_default_categories(new.id);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill for users created before this migration
do $$
declare u record;
begin
  for u in select id from auth.users loop
    perform public.seed_default_categories(u.id);
  end loop;
end;
$$;
