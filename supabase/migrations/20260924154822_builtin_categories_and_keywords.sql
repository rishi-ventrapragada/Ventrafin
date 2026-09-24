-- =============================================================================
-- Ventrafin — built-in reference data (global, not per-user)
--
-- private.builtin_categories : every category the system knows how to create,
--                              with its colour. is_starter = seeded at signup.
-- private.builtin_keywords   : merchant/biller keyword -> built-in category,
--                              the fallback list for auto-categorization.
--
-- Storage choice: small tables in the non-exposed `private` schema rather
-- than a CASE expression, so the list is plain data. It can be extended by a
-- new migration (or by the admin in the dashboard) without touching the
-- categorization function, and the tests can inspect it. Clients cannot read
-- or modify it; auto-categorization reads it via one SECURITY DEFINER function.
--
-- match_mode
--   'substring' : keyword may appear anywhere in the normalized description
--                 ('swiggy' matches 'upi swiggy icici' and 'swiggyinstamart').
--                 Used for distinctive brand names.
--   'word'      : keyword must appear as whole word(s)
--                 ('ola' matches 'ola ride' but not 'coca cola').
--                 Used for short or ambiguous keywords.
-- When several keywords match, the LONGEST wins
-- ('swiggy instamart' -> Groceries beats 'swiggy' -> Food).
-- =============================================================================

create table private.builtin_categories (
  name        text not null,
  kind        text not null check (kind in ('expense', 'income')),
  color       text not null check (color ~ '^#[0-9A-Fa-f]{6}$'),
  is_starter  boolean not null default false,
  sort_order  integer not null default 0,
  primary key (name, kind)
);

create table private.builtin_keywords (
  keyword        text not null check (char_length(keyword) >= 2 and keyword = private.normalize_text(keyword)),
  category_name  text not null,
  category_kind  text not null,
  match_mode     text not null check (match_mode in ('substring', 'word')),
  primary key (keyword, category_kind),
  foreign key (category_name, category_kind) references private.builtin_categories (name, kind) on update cascade
);

-- RLS on (with no policies) + no grants: unreachable for anon/authenticated.
alter table private.builtin_categories enable row level security;
alter table private.builtin_keywords   enable row level security;
revoke all on table private.builtin_categories, private.builtin_keywords from public, anon, authenticated;


-- -----------------------------------------------------------------------------
-- Categories
-- Starter set per PRD § 4.3 (expense) plus three income starters so income
-- entries have somewhere to go from day one (ASSUMPTION — PRD lists only
-- expense starters but requires income categories to exist).
-- Non-starter rows are created for a user only when a keyword first needs them.
-- -----------------------------------------------------------------------------
insert into private.builtin_categories (name, kind, color, is_starter, sort_order) values
  -- starter: expense (PRD § 4.3)
  ('Groceries',          'expense', '#43A047', true,  10),
  ('Bills',              'expense', '#546E7A', true,  20),
  ('Medical',            'expense', '#E53935', true,  30),
  ('Transport',          'expense', '#1E88E5', true,  40),
  ('Food',               'expense', '#FB8C00', true,  50),
  ('Electricity',        'expense', '#FBC02D', true,  60),
  ('Entertainment',      'expense', '#8E24AA', true,  70),
  ('Other',              'expense', '#9E9E9E', true,  80),
  -- starter: income
  ('Salary',             'income',  '#00897B', true, 110),
  ('Interest',           'income',  '#3949AB', true, 120),
  ('Other Income',       'income',  '#78909C', true, 130),
  -- auto-created on first match: expense
  ('Shopping',           'expense', '#D81B60', false, 200),
  ('Fuel',               'expense', '#6D4C41', false, 210),
  ('Mobile & Internet',  'expense', '#5E35B1', false, 220),
  ('Cooking Gas',        'expense', '#F4511E', false, 230),
  ('Water',              'expense', '#039BE5', false, 240),
  ('Travel',             'expense', '#00ACC1', false, 250),
  ('Insurance',          'expense', '#7CB342', false, 260),
  ('Loan EMI',           'expense', '#C62828', false, 270),
  ('Education',          'expense', '#FF7043', false, 280),
  -- auto-created on first match: income
  ('Refund',             'income',  '#26A69A', false, 300),
  ('Dividend',           'income',  '#5C6BC0', false, 310);


-- -----------------------------------------------------------------------------
-- Keywords (already in normalized form: lower-case, no punctuation, words
-- separated by single spaces; e.g. "Domino's" is written 'domino').
-- -----------------------------------------------------------------------------
with src (category_name, category_kind, substring_keywords, word_keywords) as (values
  ('Food', 'expense',
    array['swiggy', 'zomato', 'domino', 'mcdonald', 'pizza hut', 'burger king', 'starbucks',
          'haldiram', 'eatsure', 'faasos', 'chaayos', 'barbeque nation', 'restaurant'],
    array['kfc', 'subway', 'cafe', 'dhaba']),

  ('Groceries', 'expense',
    array['dmart', 'avenue supermarts', 'bigbasket', 'big basket', 'blinkit', 'grofers', 'zepto',
          'jiomart', 'instamart', 'swiggy instamart', 'reliance fresh', 'reliance smart',
          'smart bazaar', 'star bazaar', 'big bazaar', 'spencer', 'nature s basket',
          'more supermarket', 'metro cash', 'supermarket', 'grocer'],
    array['d mart', 'kirana', 'sabzi', 'vegetables', 'milk', 'dairy']),

  ('Medical', 'expense',
    array['apollo', 'medplus', 'pharmeasy', 'netmeds', 'practo', 'pharmacy', 'chemist',
          'hospital', 'diagnostic', 'pathlab', 'thyrocare', 'medicine'],
    array['1mg', 'clinic', 'medical', 'doctor']),

  ('Transport', 'expense',
    array['olacabs', 'rapido', 'namma yatri', 'bmtc', 'best bus', 'fastag', 'parking', 'auto rickshaw'],
    array['uber', 'ola', 'metro', 'cab', 'taxi']),

  ('Fuel', 'expense',
    array['indian oil', 'iocl', 'bharat petroleum', 'bpcl', 'hpcl', 'hindustan petroleum', 'nayara'],
    array['petrol', 'diesel', 'shell', 'fuel', 'cng']),

  ('Electricity', 'expense',
    array['electricity', 'discom', 'msedcl', 'mahadiscom', 'mahavitaran', 'mseb', 'bescom', 'hescom',
          'gescom', 'tangedco', 'tneb', 'tata power', 'adani electricity', 'bses', 'tpddl', 'kseb',
          'pspcl', 'uhbvn', 'dhbvn', 'apspdcl', 'tsspdcl', 'jvvnl', 'avvnl', 'jdvvnl', 'mgvcl',
          'pgvcl', 'ugvcl', 'dgvcl', 'wbsedcl', 'torrent power'],
    array['cesc', 'bijli']),

  ('Mobile & Internet', 'expense',
    array['airtel', 'vodafone', 'bsnl', 'mtnl', 'act fibernet', 'hathway', 'excitel', 'broadband',
          'mobile recharge'],
    array['jio', 'postpaid']),

  ('Cooking Gas', 'expense',
    array['indane', 'hp gas', 'bharat gas', 'bharatgas', 'mahanagar gas', 'gujarat gas',
          'adani total gas', 'gas cylinder'],
    array['igl', 'lpg']),

  ('Water', 'expense',
    array['water bill', 'jal board', 'bwssb', 'water tax', 'water charges'],
    '{}'::text[]),

  ('Entertainment', 'expense',
    array['netflix', 'hotstar', 'jiocinema', 'prime video', 'sonyliv', 'zee5', 'spotify',
          'youtube premium', 'bookmyshow', 'cinepolis', 'gaana', 'wynk'],
    array['pvr', 'inox', 'movie']),

  ('Shopping', 'expense',
    array['amazon', 'amzn', 'flipkart', 'myntra', 'ajio', 'meesho', 'nykaa', 'tata cliq', 'croma',
          'reliance digital', 'vijay sales', 'decathlon', 'shoppers stop', 'lenskart', 'firstcry',
          'snapdeal'],
    array['westside', 'ikea']),

  ('Travel', 'expense',
    array['irctc', 'makemytrip', 'goibibo', 'cleartrip', 'redbus', 'air india', 'akasa', 'spicejet',
          'vistara', 'ixigo', 'easemytrip', 'railway'],
    array['indigo', 'yatra', 'oyo', 'flight']),

  ('Insurance', 'expense',
    array['insurance', 'policybazaar', 'star health', 'hdfc ergo', 'icici lombard'],
    array['lic']),

  ('Loan EMI', 'expense',
    array['home loan', 'car loan', 'personal loan', 'education loan'],
    array['emi']),

  ('Education', 'expense',
    array['school fee', 'college fee', 'tuition', 'byju', 'unacademy'],
    array['coaching']),

  ('Bills', 'expense',
    array['tata play', 'dish tv', 'sun direct', 'airtel dth', 'house rent', 'property tax'],
    array['maintenance', 'dth', 'd2h']),

  ('Salary', 'income',
    array['payroll'],
    array['salary', 'stipend', 'wages']),

  ('Interest', 'income',
    '{}'::text[],
    array['interest']),

  ('Refund', 'income',
    '{}'::text[],
    array['refund', 'cashback', 'reversal']),

  ('Dividend', 'income',
    '{}'::text[],
    array['dividend'])
)
insert into private.builtin_keywords (keyword, category_name, category_kind, match_mode)
select kw, category_name, category_kind, 'substring' from src, unnest(substring_keywords) as kw
union all
select kw, category_name, category_kind, 'word'      from src, unnest(word_keywords)      as kw;


-- -----------------------------------------------------------------------------
-- Lookup used by the categorization trigger. SECURITY DEFINER so it can read
-- the private table; it only ever returns built-in (non-user) data.
-- -----------------------------------------------------------------------------
create function private.match_builtin_category(p_description text, p_kind text)
returns table (category_name text, category_color text)
language sql
stable
security definer
set search_path = ''
as $$
  with d as (select private.normalize_text(p_description) as txt)
  select c.name, c.color
  from d
  join private.builtin_keywords k on k.category_kind = p_kind
  join private.builtin_categories c on c.name = k.category_name and c.kind = k.category_kind
  where d.txt <> ''
    and case k.match_mode
          when 'word' then strpos(' ' || d.txt || ' ', ' ' || k.keyword || ' ') > 0
          else strpos(d.txt, k.keyword) > 0
        end
  order by char_length(k.keyword) desc, k.keyword
  limit 1;
$$;

grant execute on function private.match_builtin_category(text, text) to authenticated, service_role;
