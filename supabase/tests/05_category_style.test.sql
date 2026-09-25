-- (e) Category icons and colours: every built-in category has a curated icon
-- and a distinct colour; seeding and auto-categorization carry them over;
-- categories created without an icon/colour get sensible defaults; the icon
-- must come from the curated set. Runs as a signed-in user, through RLS.
begin;
create extension if not exists pgtap with schema extensions;

select plan(20);

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'alice@test.local', 'authenticated', 'authenticated'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'bob@test.local',   'authenticated', 'authenticated');


-- ===========================================================================
-- Built-in reference data (checked as the table owner)
-- ===========================================================================
select is_empty(
  $$ select b.name from private.builtin_categories b
     where not exists (
       select 1 from pg_constraint k
       where k.conname = 'categories_icon_check' and k.conrelid = 'public.categories'::regclass
         and pg_get_constraintdef(k.oid) like '%''' || b.icon || '''%') $$,
  'every built-in category icon is in the curated icon set'
);

select is(
  (select count(distinct upper(color))::int from private.builtin_categories),
  (select count(*)::int from private.builtin_categories),
  'every built-in category has its own colour'
);

select is(
  (select count(distinct icon)::int from private.builtin_categories),
  (select count(*)::int from private.builtin_categories),
  'every built-in category has its own icon'
);

select is_empty(
  $$ select name from private.builtin_categories where not (upper(color) = any (private.category_palette())) $$,
  'every built-in colour is in the curated palette'
);

select set_eq(
  $$ select name, icon, color from public.categories where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  $$ select name, icon, color from private.builtin_categories where is_starter $$,
  'seeded starter categories carry their built-in icon and colour'
);

select results_eq(
  $$ select name, icon from public.categories
     where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
       and name in ('Food', 'Groceries', 'Medical', 'Electricity', 'Salary')
     order by name $$,
  $$ values ('Electricity'::text, 'bolt'::text), ('Food', 'restaurant'), ('Groceries', 'shopping_cart'),
            ('Medical', 'local_hospital'), ('Salary', 'account_balance_wallet') $$,
  'Food: fork and knife, Groceries: cart, Medical: cross, Electricity: bolt, Salary: wallet'
);


-- ===========================================================================
-- As Alice
-- ===========================================================================
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);

-- Auto-categorization creates Fuel with its built-in icon and colour.
insert into public.transactions (amount_paise, description, account_id, type)
select 150000, 'Indian Oil petrol pump', id, 'expense' from public.accounts where name = 'Cash';

select results_eq(
  $$ select icon, color from public.categories where name = 'Fuel' $$,
  $$ values ('local_gas_station'::text, '#6D4C41'::text) $$,
  'auto-created Fuel gets the fuel pump icon and its built-in colour'
);

-- New categories without an icon or colour.
insert into public.categories (name, kind) values ('Temple donations', 'expense');
select results_eq(
  $$ select icon, color from public.categories where name = 'Temple donations' $$,
  $$ values ('label'::text, '#BF360C'::text) $$,
  'unknown name: tag icon and the first palette colour no category uses yet'
);

insert into public.categories (name, kind) values ('Pooja items', 'expense');
select is(
  (select color from public.categories where name = 'Pooja items'),
  '#FFAB91',
  'the next new category gets the next unused palette colour'
);

insert into public.categories (name, kind) values ('Petrol', 'expense');
select results_eq(
  $$ select icon, color from public.categories where name = 'Petrol' $$,
  $$ values ('local_gas_station'::text, '#C0CA33'::text) $$,
  'name matching a built-in keyword ("Petrol"): that category''s icon, but its own unused colour'
);

insert into public.categories (name, kind) values ('refund', 'income');
select results_eq(
  $$ select icon, color from public.categories where name = 'refund' $$,
  $$ values ('undo'::text, '#C0CA33'::text) $$,
  'name of a built-in category (any case): its built-in icon and colour'
);

insert into public.categories (name, kind, icon, color) values ('Pets', 'expense', 'pets', '#8E24AA');
select results_eq(
  $$ select icon, color from public.categories where name = 'Pets' $$,
  $$ values ('pets'::text, '#8E24AA'::text) $$,
  'an icon and colour chosen by the client are kept'
);

insert into public.categories (name, kind, icon) values ('Chai', 'expense', 'local_cafe');
select results_eq(
  $$ select icon, color from public.categories where name = 'Chai' $$,
  $$ values ('local_cafe'::text, '#AED581'::text) $$,
  'only an icon given: the colour is still filled in'
);

-- Archived categories don't hold on to their colour.
update public.categories set archived = true where name = 'Temple donations';
insert into public.categories (name, kind) values ('Gifts', 'expense');
select is(
  (select color from public.categories where name = 'Gifts'),
  '#BF360C',
  'an archived category''s colour is free for a new one'
);

select throws_ok(
  $$ insert into public.categories (name, kind, icon) values ('Logo test', 'expense', 'swiggy_logo') $$,
  '23514', null,
  'an icon outside the curated set is rejected'
);

select throws_ok(
  $$ update public.categories set icon = 'https://example.com/logo.png' where name = 'Food' $$,
  '23514', null,
  'an image URL is not an icon key'
);

select throws_ok(
  $$ update public.categories set icon = null where name = 'Food' $$,
  '23502', null,
  'icon can''t be removed'
);

update public.categories set icon = 'local_cafe', color = '#AD1457' where name = 'Food';
select results_eq(
  $$ select icon, color from public.categories where name = 'Food' $$,
  $$ values ('local_cafe'::text, '#AD1457'::text) $$,
  'the owner can change a category''s icon and colour'
);

select is_empty(
  $$ update public.categories set icon = 'pets'
     where owner_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' returning id $$,
  'another user''s categories can''t be restyled'
);

reset role;

select is_empty(
  $$ select 1 from public.categories
     where owner_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' and icon = 'pets' $$,
  'Bob''s categories are unchanged'
);

select * from finish();
rollback;
