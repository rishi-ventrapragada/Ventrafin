-- =============================================================================
-- Ventrafin — category icons and a curated colour palette (Increment 2.5)
--
-- categories.icon holds a KEY from a curated icon set (DECISIONS.md D13), not
-- an image. Keys are Google Material Symbols names ('restaurant', 'bolt', ...),
-- so both apps render them from the same open-source icon font: Flutter's
-- built-in `Icons.*`, and the Material Symbols font on the web. The curated
-- list is the CHECK constraint below; /shared/category-style.json mirrors it
-- (with labels, groups and the colour palette) for the two clients.
--
-- Defaults, filled by a BEFORE INSERT trigger when a client omits them:
--   icon   1. the built-in category with the same name and kind ('Fuel')
--          2. else a guess from the built-in keyword list ('Petrol' -> Fuel's
--             fuel pump, 'Swiggy' -> Food's fork and knife)
--          3. else 'label' (a plain tag)
--   color  1. the built-in category with the same name and kind
--          2. else the first palette colour none of the user's active
--             categories uses yet, so a new category stands out
-- Auto-categorization and signup seeding already insert built-in names, so
-- they pick up their icons through the same trigger, unchanged.
--
-- Built-in colours were also re-picked so each is visually distinct (every
-- pair of expense categories is at least CIEDE2000 15 apart). Existing
-- categories get their icon now; their colour is moved to the new built-in
-- colour only when it is still the old built-in default (never overriding a
-- colour the user chose).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Curated palette: the colours offered in the apps' colour pickers, in picker
-- order. Also the source of default colours for non-built-in categories.
-- -----------------------------------------------------------------------------
create function private.category_palette()
returns text[]
language sql
immutable
parallel safe
set search_path = ''
as $$
  select array[
    '#E53935', '#BF360C', '#FFAB91', '#FB8C00', '#FDD835', '#C0CA33',
    '#AED581', '#43A047', '#2E7D32', '#0097A7', '#4FC3F7', '#1E88E5',
    '#1565C0', '#3949AB', '#B39DDB', '#8E24AA', '#AD1457', '#EC407A',
    '#6D4C41', '#A1887F', '#546E7A', '#78909C', '#9E9E9E', '#263238'
  ]::text[];
$$;

grant execute on function private.category_palette() to authenticated, service_role;


-- -----------------------------------------------------------------------------
-- Built-in categories: icon + refreshed colours.
-- -----------------------------------------------------------------------------
create temporary table builtin_style (name text, kind text, icon text, color text);

insert into builtin_style (name, kind, icon, color) values
  ('Groceries',         'expense', 'shopping_cart',          '#43A047'),
  ('Bills',             'expense', 'receipt_long',           '#546E7A'),
  ('Medical',           'expense', 'local_hospital',         '#E53935'),
  ('Transport',         'expense', 'local_taxi',             '#1E88E5'),
  ('Food',              'expense', 'restaurant',             '#FB8C00'),
  ('Electricity',       'expense', 'bolt',                   '#FDD835'),
  ('Entertainment',     'expense', 'movie',                  '#8E24AA'),
  ('Other',             'expense', 'more_horiz',             '#9E9E9E'),
  ('Shopping',          'expense', 'shopping_bag',           '#EC407A'),
  ('Fuel',              'expense', 'local_gas_station',      '#6D4C41'),
  ('Mobile & Internet', 'expense', 'smartphone',             '#3949AB'),
  ('Cooking Gas',       'expense', 'propane_tank',           '#FFAB91'),
  ('Water',             'expense', 'water_drop',             '#4FC3F7'),
  ('Travel',            'expense', 'flight',                 '#0097A7'),
  ('Insurance',         'expense', 'shield',                 '#AED581'),
  ('Loan EMI',          'expense', 'event_repeat',           '#263238'),
  ('Education',         'expense', 'school',                 '#B39DDB'),
  ('Salary',            'income',  'account_balance_wallet', '#2E7D32'),
  ('Interest',          'income',  'percent',                '#1565C0'),
  ('Other Income',      'income',  'currency_rupee',         '#78909C'),
  ('Refund',            'income',  'undo',                   '#C0CA33'),
  ('Dividend',          'income',  'trending_up',            '#AD1457');

-- Existing users: move colours that are still the OLD built-in default to the
-- new one. (Runs before the built-in table is updated, while it still holds
-- the old colours.)
update public.categories c
   set color = s.color
  from builtin_style s
  join private.builtin_categories b on b.name = s.name and b.kind = s.kind
 where c.kind = s.kind
   and lower(btrim(c.name)) = lower(s.name)
   and upper(c.color) = upper(b.color)
   and upper(c.color) <> upper(s.color);

alter table private.builtin_categories add column icon text;

update private.builtin_categories b
   set icon = s.icon, color = s.color
  from builtin_style s
 where b.name = s.name and b.kind = s.kind;

alter table private.builtin_categories alter column icon set not null;

drop table builtin_style;


-- -----------------------------------------------------------------------------
-- Default style for a category name. SECURITY DEFINER so it can read the
-- private built-in tables; it only ever returns built-in (non-user) data.
-- color is NULL for a keyword guess: a category that merely resembles a
-- built-in one gets its icon but its own colour.
-- -----------------------------------------------------------------------------
create function private.builtin_category_style(p_name text, p_kind text)
returns table (icon text, color text)
language sql
stable
security definer
set search_path = ''
as $$
  select s.icon, s.color
  from (
    select b.icon, b.color, 1 as priority
    from private.builtin_categories b
    where b.kind = p_kind and lower(b.name) = lower(btrim(p_name))
    union all
    select b.icon, null::text, 2
    from private.match_builtin_category(p_name, p_kind) m
    join private.builtin_categories b on b.name = m.category_name and b.kind = p_kind
  ) s
  order by s.priority
  limit 1;
$$;

grant execute on function private.builtin_category_style(text, text) to authenticated, service_role;


-- -----------------------------------------------------------------------------
-- public.categories.icon
-- -----------------------------------------------------------------------------
alter table public.categories add column icon text;

update public.categories c
   set icon = coalesce((select s.icon from private.builtin_category_style(c.name, c.kind) s), 'label');

alter table public.categories
  alter column icon set not null,
  add constraint categories_icon_check check (icon in (
    -- general
    'label', 'more_horiz',
    -- food & home
    'restaurant', 'local_cafe', 'fastfood', 'bakery_dining', 'shopping_cart', 'house',
    'cleaning_services', 'local_laundry_service', 'handyman', 'pets',
    -- bills & utilities
    'receipt_long', 'bolt', 'water_drop', 'propane_tank', 'smartphone', 'wifi', 'tv',
    'event_repeat', 'request_quote',
    -- transport & travel
    'local_taxi', 'directions_car', 'two_wheeler', 'directions_bus', 'train',
    'local_gas_station', 'local_parking', 'flight', 'luggage',
    -- health & family
    'local_hospital', 'medication', 'local_pharmacy', 'fitness_center', 'spa',
    'child_care', 'elderly', 'family_restroom', 'school', 'menu_book',
    -- shopping & leisure
    'shopping_bag', 'checkroom', 'content_cut', 'card_giftcard', 'celebration', 'movie',
    'sports_esports', 'sports_cricket', 'temple_hindu', 'volunteer_activism',
    -- money
    'account_balance_wallet', 'currency_rupee', 'percent', 'savings', 'trending_up',
    'undo', 'redeem', 'work', 'sell', 'shield', 'real_estate_agent'
  ));

comment on column public.categories.icon  is 'Key from the curated icon set (Material Symbols name); see /shared/category-style.json.';
comment on column public.categories.color is '#RRGGBB. Omit on insert to get the built-in colour or an unused palette colour.';

-- The trigger below picks the colour; a fixed grey default would hide it.
alter table public.categories alter column color drop default;


-- -----------------------------------------------------------------------------
-- BEFORE INSERT: fill in icon / colour the client left out.
-- SECURITY INVOKER: the "unused colour" lookup reads the caller's own
-- categories under RLS.
-- -----------------------------------------------------------------------------
create function private.categories_default_style()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_icon  text;
  v_color text;
begin
  if new.icon is not null and new.color is not null then
    return new;
  end if;

  select s.icon, s.color into v_icon, v_color
  from private.builtin_category_style(new.name, new.kind) s;

  new.icon := coalesce(new.icon, v_icon, 'label');

  if new.color is null then
    new.color := coalesce(
      v_color,
      (select p.color
         from unnest(private.category_palette()) with ordinality as p(color, ord)
        where not exists (
                select 1 from public.categories c
                 where c.owner_id = new.owner_id
                   and not c.archived
                   and upper(c.color) = upper(p.color))
        order by p.ord
        limit 1),
      -- every palette colour is taken: reuse one, spread by name
      (private.category_palette())[1 + ((hashtext(lower(btrim(new.name)))::bigint % 24) + 24) % 24]
    );
  end if;

  return new;
end;
$$;

create trigger categories_default_style
  before insert on public.categories
  for each row execute function private.categories_default_style();
