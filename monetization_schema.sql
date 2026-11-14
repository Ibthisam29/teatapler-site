-- =====================================================================
-- TEATAPLER MONETIZATION SCHEMA — paste into Supabase SQL Editor and run
-- Run this AFTER the main schema.sql. Safe to re-run (uses IF NOT EXISTS).
-- =====================================================================

-- ───────────────────── SUBSCRIPTION PLANS ─────────────────────
create table if not exists public.subscription_plans (
  id            uuid primary key default uuid_generate_v4(),
  name          text not null,
  slug          text unique not null,
  tagline       text,
  description   text,
  price_monthly numeric(10,2) not null,
  price_yearly  numeric(10,2),
  perks         text[] default '{}',
  stripe_link   text,
  stripe_link_yearly text,
  tier          text not null default 'classic' check (tier in ('classic','reserve','atelier')),
  sort_order    integer default 0,
  is_featured   boolean default false,
  status        text not null default 'draft' check (status in ('draft','published','archived')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
alter table public.subscription_plans enable row level security;
drop policy if exists "Public read published plans" on public.subscription_plans;
create policy "Public read published plans" on public.subscription_plans
  for select using (status='published');
drop policy if exists "Admins manage plans" on public.subscription_plans;
create policy "Admins manage plans" on public.subscription_plans
  for all using (auth.role()='authenticated') with check (auth.role()='authenticated');

-- Seed starter tiers (idempotent)
insert into public.subscription_plans (name, slug, tagline, description, price_monthly, price_yearly, perks, tier, sort_order, is_featured, status)
values
  ('Classic', 'classic', 'A curated monthly tin', 'Three signature teas delivered to your door each month.', 45.00, 480.00,
    array['3 teas per month','Free domestic shipping','Cancel anytime'], 'classic', 1, false, 'published'),
  ('Reserve', 'reserve', 'Heritage selection, personally chosen', 'Rare and seasonal harvests reserved for members, with tasting notes handwritten by our master blender.',
    95.00, 1020.00,
    array['4 rare teas per month','Tasting notes included','Priority event access','Free global shipping'], 'reserve', 2, true, 'published'),
  ('Atelier', 'atelier', 'Private atelier membership', 'Bespoke blends crafted for you, plus Sidr honey pairings and quarterly private tastings.',
    180.00, 1920.00,
    array['Bespoke monthly blend','Sidr honey pairing','Quarterly private tasting','Concierge access','Complimentary gifting'], 'atelier', 3, false, 'published')
on conflict (slug) do nothing;

-- ───────────────────── EVENT TICKETING ─────────────────────
alter table public.events add column if not exists price           numeric(10,2) default 0;
alter table public.events add column if not exists stripe_link     text;
alter table public.events add column if not exists tickets_sold    integer default 0;
alter table public.events add column if not exists requires_payment boolean default false;

create table if not exists public.event_tickets (
  id            uuid primary key default uuid_generate_v4(),
  event_id      uuid references public.events(id) on delete cascade,
  email         text not null,
  name          text,
  phone         text,
  guests        integer default 1,
  amount_paid   numeric(10,2),
  stripe_session_id text,
  payment_status text default 'pending' check (payment_status in ('pending','paid','refunded','failed')),
  created_at    timestamptz not null default now()
);
alter table public.event_tickets enable row level security;
drop policy if exists "Public create tickets" on public.event_tickets;
create policy "Public create tickets" on public.event_tickets for insert with check (true);
drop policy if exists "Admins read tickets" on public.event_tickets;
create policy "Admins read tickets" on public.event_tickets for select using (auth.role()='authenticated');

-- ───────────────────── GIFT CARDS ─────────────────────
create table if not exists public.gift_cards (
  id            uuid primary key default uuid_generate_v4(),
  code          text unique not null,
  denomination  numeric(10,2) not null,
  balance       numeric(10,2) not null,
  purchased_by_email text,
  recipient_email text,
  recipient_name text,
  message       text,
  stripe_session_id text,
  status        text not null default 'active' check (status in ('active','redeemed','expired','pending')),
  expires_at    timestamptz,
  created_at    timestamptz not null default now()
);
alter table public.gift_cards enable row level security;
drop policy if exists "Public create gift cards" on public.gift_cards;
create policy "Public create gift cards" on public.gift_cards for insert with check (true);
drop policy if exists "Admins manage gift cards" on public.gift_cards;
create policy "Admins manage gift cards" on public.gift_cards for all using (auth.role()='authenticated') with check (auth.role()='authenticated');

create table if not exists public.gift_card_denominations (
  id            uuid primary key default uuid_generate_v4(),
  amount        numeric(10,2) not null unique,
  stripe_link   text,
  is_active     boolean default true,
  sort_order    integer default 0,
  created_at    timestamptz not null default now()
);
alter table public.gift_card_denominations enable row level security;
drop policy if exists "Public read denominations" on public.gift_card_denominations;
create policy "Public read denominations" on public.gift_card_denominations for select using (is_active=true);
drop policy if exists "Admins manage denominations" on public.gift_card_denominations;
create policy "Admins manage denominations" on public.gift_card_denominations for all using (auth.role()='authenticated') with check (auth.role()='authenticated');

-- Seed common gift card amounts
insert into public.gift_card_denominations (amount, sort_order, is_active)
values (50, 1, true), (100, 2, true), (200, 3, true), (500, 4, true), (1000, 5, true)
on conflict (amount) do nothing;

-- ───────────────────── BUNDLES / UPSELLS ─────────────────────
create table if not exists public.bundles (
  id            uuid primary key default uuid_generate_v4(),
  name          text not null,
  slug          text unique not null,
  tagline       text,
  description   text,
  price         numeric(10,2) not null,
  compare_at    numeric(10,2),
  product_ids   uuid[] default '{}',
  image_url     text,
  stripe_link   text,
  status        text not null default 'draft' check (status in ('draft','published','archived')),
  sort_order    integer default 0,
  created_at    timestamptz not null default now()
);
alter table public.bundles enable row level security;
drop policy if exists "Public read bundles" on public.bundles;
create policy "Public read bundles" on public.bundles for select using (status='published');
drop policy if exists "Admins manage bundles" on public.bundles;
create policy "Admins manage bundles" on public.bundles for all using (auth.role()='authenticated') with check (auth.role()='authenticated');

-- ───────────────────── UPDATED-AT TRIGGERS ─────────────────────
drop trigger if exists set_subscription_plans_updated_at on public.subscription_plans;
create trigger set_subscription_plans_updated_at before update on public.subscription_plans
  for each row execute procedure public.set_updated_at();

-- ───────────────────── DONE ─────────────────────
select 'Monetization schema applied ✦' as status;
