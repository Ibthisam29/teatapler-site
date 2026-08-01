-- TEATAPLER SUPABASE SCHEMA — paste into SQL Editor and run

create extension if not exists "uuid-ossp";

-- ADMIN PROFILES
create table if not exists public.admin_profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  email        text not null,
  display_name text,
  role         text not null default 'editor' check (role in ('owner','editor','viewer')),
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);
alter table public.admin_profiles enable row level security;
create policy "Admins read own profile" on public.admin_profiles for select using (auth.uid() = id);
create policy "Owner manage profiles" on public.admin_profiles for all using (
  exists(select 1 from public.admin_profiles p where p.id=auth.uid() and p.role='owner')
);

-- SITE SETTINGS
create table if not exists public.site_settings (
  key text primary key, value text, updated_at timestamptz default now()
);
alter table public.site_settings enable row level security;
create policy "Public read settings" on public.site_settings for select using (true);
create policy "Admins write settings" on public.site_settings for all using (auth.role()='authenticated') with check (auth.role()='authenticated');
insert into public.site_settings (key,value) values
  ('launch_date','2026-09-01'),('seed_count','247'),('contact_email','hello@teatapler.com'),
  ('instagram_url','https://instagram.com/teatapler'),('twitter_url','https://twitter.com/teatapler'),
  ('facebook_url','https://facebook.com/teatapler'),('linkedin_url','https://linkedin.com/company/teatapler'),
  ('hero_headline','Indulge in the <em>Elegance</em> of Tea'),
  ('hero_sub','A curated collection of rare teas and Sidr honey pairings — where ancient craft meets modern refinement.'),
  ('banner_enabled','false'),('banner_text',''),('ga4_id','')
on conflict (key) do nothing;

-- COLLECTIONS
create table if not exists public.collections (
  id uuid primary key default uuid_generate_v4(), name text not null unique, slug text not null unique,
  description text, sort_order int default 0, created_at timestamptz default now()
);
alter table public.collections enable row level security;
create policy "Public read collections" on public.collections for select using (true);
create policy "Admins manage collections" on public.collections for all using (auth.role()='authenticated') with check (auth.role()='authenticated');
insert into public.collections (name,slug,sort_order) values
  ('TeaTapler Classics','classics',1),('Heritage Reserve','heritage',2),
  ('Atelier Collection','atelier',3),('Limited Edition','limited',4)
on conflict do nothing;

-- UPDATED_AT TRIGGER FUNCTION
create or replace function public.set_updated_at() returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end; $$;

-- PRODUCTS
create table if not exists public.products (
  id uuid primary key default uuid_generate_v4(), name text not null, slug text not null unique,
  collection_id uuid references public.collections(id) on delete set null,
  emoji text not null default '🍃', description text, base_price numeric(10,2) not null,
  tag text not null default 'featured' check (tag in ('featured','new','limited','seasonal','artisan')),
  status text not null default 'draft' check (status in ('published','draft','archived')),
  prep_notes text, stripe_link text, sort_order int default 0,
  created_at timestamptz default now(), updated_at timestamptz default now()
);
alter table public.products enable row level security;
create trigger products_updated_at before update on public.products for each row execute function public.set_updated_at();
create policy "Public read published products" on public.products for select using (status='published');
create policy "Admins read all products" on public.products for select using (auth.role()='authenticated');
create policy "Admins manage products" on public.products for insert update delete using (auth.role()='authenticated') with check (auth.role()='authenticated');

-- PRODUCT SIZES
create table if not exists public.product_sizes (
  id uuid primary key default uuid_generate_v4(), product_id uuid not null references public.products(id) on delete cascade,
  label text not null, price numeric(10,2), status text not null default 'available'
    check (status in ('available','oos','preorder')), sort_order int default 0
);
alter table public.product_sizes enable row level security;
create policy "Public read product sizes" on public.product_sizes for select using (true);
create policy "Admins manage product sizes" on public.product_sizes for all using (auth.role()='authenticated') with check (auth.role()='authenticated');

-- PRODUCT MEDIA
create table if not exists public.product_media (
  id uuid primary key default uuid_generate_v4(), product_id uuid not null references public.products(id) on delete cascade,
  url text not null, type text not null default 'image' check (type in ('image','video')),
  is_primary boolean default false, sort_order int default 0, created_at timestamptz default now()
);
alter table public.product_media enable row level security;
create policy "Public read product media" on public.product_media for select using (true);
create policy "Admins manage product media" on public.product_media for all using (auth.role()='authenticated') with check (auth.role()='authenticated');

-- EVENTS
create table if not exists public.events (
  id uuid primary key default uuid_generate_v4(), title text not null,
  slug text not null unique default md5(random()::text),
  event_date date not null, event_time time, location text,
  capacity int default 20, rsvp_count int default 0, price numeric(10,2) default 0,
  status text not null default 'draft' check (status in ('published','draft','sold-out','cancelled')),
  description text, stripe_link text, cover_url text,
  created_at timestamptz default now(), updated_at timestamptz default now()
);
alter table public.events enable row level security;
create trigger events_updated_at before update on public.events for each row execute function public.set_updated_at();
create policy "Public read published events" on public.events for select using (status in ('published','sold-out'));
create policy "Admins read all events" on public.events for select using (auth.role()='authenticated');
create policy "Admins manage events" on public.events for insert update delete using (auth.role()='authenticated') with check (auth.role()='authenticated');

-- EVENT RSVPs
create table if not exists public.event_rsvps (
  id uuid primary key default uuid_generate_v4(), event_id uuid not null references public.events(id) on delete cascade,
  name text not null, email text not null, guests int default 1 check (guests between 1 and 10),
  created_at timestamptz default now()
);
alter table public.event_rsvps enable row level security;
create policy "Public insert rsvps" on public.event_rsvps for insert with check (true);
create policy "Admins read rsvps" on public.event_rsvps for select using (auth.role()='authenticated');
create policy "Admins delete rsvps" on public.event_rsvps for delete using (auth.role()='authenticated');

create or replace function public.increment_rsvp_count() returns trigger language plpgsql security definer as $$
begin update public.events set rsvp_count=rsvp_count+new.guests where id=new.event_id; return new; end; $$;
create trigger on_rsvp_insert after insert on public.event_rsvps for each row execute function public.increment_rsvp_count();

-- JOURNAL POSTS
create table if not exists public.journal_posts (
  id uuid primary key default uuid_generate_v4(), title text not null, slug text not null unique,
  category text default 'Ritual' check (category in ('Ritual','Culture','Heritage','Recipe','News')),
  read_minutes int default 4, cover_url text, content text,
  status text default 'draft' check (status in ('published','draft')), sort_order int default 0,
  created_at timestamptz default now(), updated_at timestamptz default now()
);
alter table public.journal_posts enable row level security;
create trigger journal_updated_at before update on public.journal_posts for each row execute function public.set_updated_at();
create policy "Public read published posts" on public.journal_posts for select using (status='published');
create policy "Admins read all posts" on public.journal_posts for select using (auth.role()='authenticated');
create policy "Admins manage posts" on public.journal_posts for insert update delete using (auth.role()='authenticated') with check (auth.role()='authenticated');
insert into public.journal_posts (title,slug,category,read_minutes,status,sort_order) values
  ('The Art of Stillness','the-art-of-stillness','Ritual',4,'published',1),
  ('Craftsmanship in a Cup','craftsmanship-in-a-cup','Culture',6,'published',2),
  ('Culture Meets Modern Elegance','culture-meets-elegance','Heritage',5,'published',3)
on conflict do nothing;

-- PREORDERS
create table if not exists public.preorders (
  id uuid primary key default uuid_generate_v4(), name text not null, email text not null,
  country text, interest text, created_at timestamptz default now()
);
alter table public.preorders enable row level security;
create policy "Public insert preorders" on public.preorders for insert with check (true);
create policy "Admins read preorders" on public.preorders for select using (auth.role()='authenticated');
create policy "Admins delete preorders" on public.preorders for delete using (auth.role()='authenticated');

-- SUBSCRIBERS (VIP + Newsletter)
create table if not exists public.subscribers (
  id uuid primary key default uuid_generate_v4(), email text not null unique,
  list text default 'newsletter' check (list in ('vip','newsletter','events-waitlist')),
  created_at timestamptz default now()
);
alter table public.subscribers enable row level security;
create policy "Public insert subscribers" on public.subscribers for insert with check (true);
create policy "Admins read subscribers" on public.subscribers for select using (auth.role()='authenticated');
create policy "Admins delete subscribers" on public.subscribers for delete using (auth.role()='authenticated');

-- PAYMENT LINKS
create table if not exists public.payment_links (
  id uuid primary key default uuid_generate_v4(), key text not null unique,
  url text default '', label text, updated_at timestamptz default now()
);
alter table public.payment_links enable row level security;
create policy "Public read payment links" on public.payment_links for select using (true);
create policy "Admins manage payment links" on public.payment_links for all using (auth.role()='authenticated') with check (auth.role()='authenticated');
insert into public.payment_links (key,label) values
  ('preorder','General Pre-Order'),('imperial_dawn','Imperial Dawn'),('emerald_whisper','Emerald Whisper'),
  ('sakura_mist','Sakura Mist'),('golden_hour','Golden Hour'),('crimson_veil','Crimson Veil'),
  ('sidr_honey','Sidr Honey Pairing'),('event_tasting','Event Ticket'),('gift_set','Gift Set')
on conflict do nothing;

-- HOMEPAGE SECTIONS
create table if not exists public.homepage_sections (
  id uuid primary key default uuid_generate_v4(), section_key text not null unique,
  title text, subtitle text, body text, cta_label text, cta_url text,
  media_url text, enabled boolean default true, updated_at timestamptz default now()
);
alter table public.homepage_sections enable row level security;
create trigger homepage_updated_at before update on public.homepage_sections for each row execute function public.set_updated_at();
create policy "Public read sections" on public.homepage_sections for select using (enabled=true);
create policy "Admins manage sections" on public.homepage_sections for all using (auth.role()='authenticated') with check (auth.role()='authenticated');
insert into public.homepage_sections (section_key,title,subtitle) values
  ('hero','Indulge in the <em>Elegance</em> of Tea','A curated collection of rare teas.'),
  ('experience','Where Every Sip Tells a Story','From the jasmine fields of the East.'),
  ('about','Where Ancient Ritual Meets Modern Grace',null)
on conflict do nothing;

-- INSERT DEFAULT PRODUCTS WITH SIZES
do $$
declare
  classic_id uuid; heritage_id uuid; atelier_id uuid; p_id uuid;
begin
  select id into classic_id  from public.collections where slug='classics';
  select id into heritage_id from public.collections where slug='heritage';
  select id into atelier_id  from public.collections where slug='atelier';

  insert into public.products (name,slug,collection_id,emoji,description,base_price,tag,status,prep_notes,sort_order) values
    ('Imperial Dawn','imperial-dawn',classic_id,'☕','Bergamot, amber and citrus. High caffeine. Bold and awakening.',42,'featured','published','Steep at 95°C for 3–4 minutes.',1),
    ('Emerald Whisper','emerald-whisper',classic_id,'🍵','Jasmine petals with morning dew green. Low caffeine. Delicate.',38,'new','published','Steep at 75°C for 2–3 minutes.',2),
    ('Sakura Mist','sakura-mist',heritage_id,'🌸','Cherry blossom and milk oolong. Low caffeine. Limited.',68,'limited','published','Steep at 85°C for 3 minutes.',3),
    ('Golden Hour','golden-hour',heritage_id,'✨','Warm honey, vanilla and spice. Medium caffeine.',72,'seasonal','published','Steep at 90°C for 4 minutes.',4),
    ('Crimson Veil','crimson-veil',classic_id,'🌹','Rose petals, cherry and earth. Medium caffeine.',45,'artisan','published','Steep at 95°C for 3–4 minutes.',5),
    ('Sidr Honey Pairing','sidr-honey-pairing',atelier_id,'🍯','Hand-harvested Sidr Honey paired with your chosen blend.',95,'featured','published','Drizzle into warm tea.',6)
  on conflict (slug) do nothing;

  select id into p_id from public.products where slug='imperial-dawn';
  insert into public.product_sizes (product_id,label,price,status,sort_order) values (p_id,'50g',42,'available',1),(p_id,'100g',78,'available',2),(p_id,'250g',null,'preorder',3) on conflict do nothing;
  select id into p_id from public.products where slug='emerald-whisper';
  insert into public.product_sizes (product_id,label,price,status,sort_order) values (p_id,'50g',38,'available',1),(p_id,'100g',72,'available',2) on conflict do nothing;
  select id into p_id from public.products where slug='sakura-mist';
  insert into public.product_sizes (product_id,label,price,status,sort_order) values (p_id,'50g',68,'available',1),(p_id,'100g',null,'oos',2) on conflict do nothing;
  select id into p_id from public.products where slug='golden-hour';
  insert into public.product_sizes (product_id,label,price,status,sort_order) values (p_id,'50g',72,'preorder',1),(p_id,'100g',null,'preorder',2) on conflict do nothing;
  select id into p_id from public.products where slug='crimson-veil';
  insert into public.product_sizes (product_id,label,price,status,sort_order) values (p_id,'50g',45,'available',1),(p_id,'100g',82,'available',2) on conflict do nothing;
  select id into p_id from public.products where slug='sidr-honey-pairing';
  insert into public.product_sizes (product_id,label,price,status,sort_order) values (p_id,'1 Jar',95,'available',1),(p_id,'3 Jars',270,'available',2) on conflict do nothing;
end $$;

-- PRODUCTS VIEW WITH SIZES
create or replace view public.products_with_sizes as
select p.*, c.name as collection_name, c.slug as collection_slug,
  coalesce(json_agg(json_build_object('id',ps.id,'label',ps.label,'price',coalesce(ps.price,p.base_price),'status',ps.status,'sort_order',ps.sort_order) order by ps.sort_order) filter (where ps.id is not null),'[]') as sizes,
  (select pm.url from public.product_media pm where pm.product_id=p.id and pm.is_primary=true limit 1) as primary_image_url
from public.products p
left join public.collections c on c.id=p.collection_id
left join public.product_sizes ps on ps.product_id=p.id
group by p.id, c.id;
