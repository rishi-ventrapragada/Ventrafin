-- =============================================================================
-- Ventrafin — core tables (ARCHITECTURE.md § 2)
--
-- Conventions
--   * Money is integer paise in `bigint`. The upper bound (< 10^15) keeps every
--     value inside JavaScript's safe-integer range, since PostgREST serialises
--     bigint as a JSON number.
--   * Every user-owned table has owner_id -> auth.users, defaulting to
--     auth.uid(), so clients may omit it (RLS still verifies it).
--   * Child rows reference parents through COMPOSITE foreign keys
--     (owner_id, x_id) -> parent (owner_id, id). FK checks bypass RLS, so a
--     plain FK would let a user attach a transaction to someone else's account
--     id. The composite FK makes cross-user references impossible.
--   * Parents referenced by transactions / bills use NO ACTION on delete:
--     an account or category that is in use cannot be deleted (archive the
--     category instead). NO ACTION rather than RESTRICT so that deleting an
--     auth user still cascades cleanly through all of that user's tables.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- profiles: one row per auth user, created by trigger at signup
-- -----------------------------------------------------------------------------
create table public.profiles (
  id                      uuid primary key references auth.users (id) on delete cascade,
  theme                   text not null default 'ocean'
                          constraint profiles_theme_check
                          check (theme in ('ocean', 'sunset', 'forest', 'garden', 'sunflower', 'marigold')),
  daily_reminder_enabled  boolean not null default true,
  bill_reminders_enabled  boolean not null default true,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

comment on table  public.profiles is 'Per-user settings. id = auth.users.id (acts as owner_id).';
comment on column public.profiles.bill_reminders_enabled is 'Master switch for bill/EMI reminders.';


-- -----------------------------------------------------------------------------
-- accounts: Cash / Bank / Credit Card
-- -----------------------------------------------------------------------------
create table public.accounts (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name        text not null constraint accounts_name_check check (char_length(btrim(name)) between 1 and 60),
  type        text not null constraint accounts_type_check check (type in ('cash', 'bank', 'credit')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- Target for composite FKs; also serves as the owner_id index.
  constraint accounts_owner_id_id_key unique (owner_id, id)
);

create unique index accounts_owner_name_key on public.accounts (owner_id, lower(btrim(name)));


-- -----------------------------------------------------------------------------
-- categories: expense / income; "Uncategorized" is category_id IS NULL,
-- so that name is reserved.
-- -----------------------------------------------------------------------------
create table public.categories (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name        text not null
              constraint categories_name_check
              check (char_length(btrim(name)) between 1 and 40 and lower(btrim(name)) <> 'uncategorized'),
  kind        text not null constraint categories_kind_check check (kind in ('expense', 'income')),
  color       text not null default '#9E9E9E'
              constraint categories_color_check check (color ~ '^#[0-9A-Fa-f]{6}$'),
  archived    boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- Target for composite FKs; also serves as the owner_id index.
  constraint categories_owner_id_id_key unique (owner_id, id)
);

-- One category per (user, kind, case-insensitive name). Auto-categorization
-- relies on this to find-or-create categories without duplicates.
create unique index categories_owner_kind_name_key on public.categories (owner_id, kind, lower(btrim(name)));


-- -----------------------------------------------------------------------------
-- category_rules: learned keyword -> category mappings (per user)
-- keyword is stored normalized (see private.normalize_text) by trigger.
-- -----------------------------------------------------------------------------
create table public.category_rules (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  keyword      text not null constraint category_rules_keyword_check check (char_length(keyword) between 2 and 100),
  category_id  uuid not null,
  hit_count    integer not null default 1 constraint category_rules_hit_count_check check (hit_count >= 1),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint category_rules_category_fkey
    foreign key (owner_id, category_id) references public.categories (owner_id, id) on delete cascade,
  -- Also serves as the owner_id index.
  constraint category_rules_owner_keyword_key unique (owner_id, keyword)
);

create index category_rules_owner_category_idx on public.category_rules (owner_id, category_id);

comment on column public.category_rules.keyword   is 'Normalized phrase; matches when it appears as whole word(s) in the normalized description.';
comment on column public.category_rules.hit_count is 'How many times the user has confirmed this mapping; used as a tie-breaker.';


-- -----------------------------------------------------------------------------
-- transactions
-- -----------------------------------------------------------------------------
create table public.transactions (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date              date not null default private.local_today()
                    constraint transactions_date_check check (date >= date '1990-01-01' and date < date '2100-01-01'),
  amount_paise      bigint not null
                    constraint transactions_amount_paise_check check (amount_paise > 0 and amount_paise < 1000000000000000),
  description       text not null default ''
                    constraint transactions_description_check check (char_length(description) <= 500),
  account_id        uuid not null,
  to_account_id     uuid,
  category_id       uuid,
  payment_method    text constraint transactions_payment_method_check check (payment_method in ('cash', 'upi', 'debit', 'card')),
  type              text not null constraint transactions_type_check check (type in ('expense', 'income', 'transfer')),
  auto_categorized  boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  -- to_account_id is required for transfers and forbidden otherwise.
  constraint transactions_transfer_target_check   check ((type = 'transfer') = (to_account_id is not null)),
  constraint transactions_transfer_distinct_check check (to_account_id is null or to_account_id <> account_id),
  -- Transfers move money between own accounts; they are never categorized.
  constraint transactions_transfer_uncategorized_check check (type <> 'transfer' or category_id is null),

  constraint transactions_account_fkey
    foreign key (owner_id, account_id)    references public.accounts (owner_id, id),
  constraint transactions_to_account_fkey
    foreign key (owner_id, to_account_id) references public.accounts (owner_id, id),
  constraint transactions_category_fkey
    foreign key (owner_id, category_id)   references public.categories (owner_id, id)
);

-- Main access path: a user's transactions by date (lists, month reports).
-- Leads with owner_id, so it is also the owner_id index.
create index transactions_owner_date_idx     on public.transactions (owner_id, date desc);
-- FK support (parent delete checks, per-account / per-category filters).
create index transactions_owner_account_idx  on public.transactions (owner_id, account_id);
create index transactions_owner_to_account_idx on public.transactions (owner_id, to_account_id) where to_account_id is not null;
create index transactions_owner_category_idx on public.transactions (owner_id, category_id);

comment on column public.transactions.amount_paise     is 'Always positive; direction comes from type.';
comment on column public.transactions.category_id      is 'NULL = Uncategorized.';
comment on column public.transactions.auto_categorized is 'Set by the categorization trigger; clients cannot set it directly.';


-- -----------------------------------------------------------------------------
-- recurring_bills: utility bills and loan EMIs
-- -----------------------------------------------------------------------------
create table public.recurring_bills (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name              text not null constraint recurring_bills_name_check check (char_length(btrim(name)) between 1 and 60),
  kind              text not null constraint recurring_bills_kind_check check (kind in ('utility', 'emi')),
  amount_paise      bigint not null
                    constraint recurring_bills_amount_paise_check check (amount_paise > 0 and amount_paise < 1000000000000000),
  due_day           integer not null constraint recurring_bills_due_day_check check (due_day between 1 and 31),
  account_id        uuid not null,
  category_id       uuid,
  reminder_enabled  boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  constraint recurring_bills_account_fkey
    foreign key (owner_id, account_id)  references public.accounts (owner_id, id),
  constraint recurring_bills_category_fkey
    foreign key (owner_id, category_id) references public.categories (owner_id, id)
);

create index recurring_bills_owner_account_idx  on public.recurring_bills (owner_id, account_id);
create index recurring_bills_owner_category_idx on public.recurring_bills (owner_id, category_id);

comment on column public.recurring_bills.due_day is 'Day of month 1-31; clients clamp to the last day for shorter months.';


-- -----------------------------------------------------------------------------
-- updated_at triggers
-- -----------------------------------------------------------------------------
create trigger profiles_set_updated_at        before update on public.profiles        for each row execute function private.set_updated_at();
create trigger accounts_set_updated_at        before update on public.accounts        for each row execute function private.set_updated_at();
create trigger categories_set_updated_at      before update on public.categories      for each row execute function private.set_updated_at();
create trigger category_rules_set_updated_at  before update on public.category_rules  for each row execute function private.set_updated_at();
create trigger transactions_set_updated_at    before update on public.transactions    for each row execute function private.set_updated_at();
create trigger recurring_bills_set_updated_at before update on public.recurring_bills for each row execute function private.set_updated_at();
