-- =============================================================================
-- Ventrafin — auto-categorization + learning from corrections
-- (PRD § 4.4, ARCHITECTURE.md § 3)
--
-- Implemented once, here, so the phone and web app behave identically.
--
-- BEFORE INSERT/UPDATE on transactions (private.transactions_before_write):
--   * transfer            -> category cleared, never auto-categorized
--   * category supplied   -> kept as-is, auto_categorized = false
--   * category unchanged on UPDATE -> kept, auto_categorized flag preserved
--   * category_id IS NULL -> try, in order:
--       1. the user's learned rules (category_rules)
--       2. the built-in Indian merchant/biller keyword list
--          (creating that category for the user if they don't have it yet)
--       3. otherwise leave NULL (= Uncategorized)
--     auto_categorized = true only when step 1 or 2 assigned a category.
--
--   Only categories of the matching kind are considered (expense transaction
--   -> expense categories, income -> income). Archived categories are skipped
--   and never resurrected: if the match points at an archived category the
--   transaction stays Uncategorized.
--
-- AFTER UPDATE OF category_id (private.learn_category_rule):
--   when the USER changes a transaction's category (fixing a wrong auto
--   category, or categorizing an uncategorized one), upsert a rule
--   "<phrase from description> -> <new category>". Repeating the same
--   correction increments hit_count; a different correction re-points the
--   rule and resets hit_count to 1. Because learned rules are checked before
--   built-in keywords, the correction wins from the next entry onward.
--
-- The trigger functions are SECURITY INVOKER: they read and create rows with
-- the caller's own privileges, so RLS applies to them like any client query.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- category_rules.keyword is always stored normalized, so user-entered rules
-- ('Amazon', 'D-Mart') match the same way as learned ones.
-- -----------------------------------------------------------------------------
create function private.category_rules_normalize()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.keyword := private.normalize_text(new.keyword);
  return new;
end;
$$;

create trigger category_rules_normalize
  before insert or update of keyword on public.category_rules
  for each row execute function private.category_rules_normalize();


-- -----------------------------------------------------------------------------
-- Rule keyword derived from a description when the user corrects a category:
-- the normalized description with leading/trailing filler words (upi, paid,
-- to, bill, order, ...) removed, capped at 4 words.
--   'UPI/Paid to Ramesh Kirana Store for veg' -> 'ramesh kirana store'
--   'Apollo Tyres - puncture 250'             -> 'apollo tyres puncture'
--   'Swiggy order #8841'                      -> 'swiggy'
-- Returns NULL when nothing meaningful is left (then no rule is learned).
-- -----------------------------------------------------------------------------
create function private.rule_keyword_from_description(p_description text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  c_filler constant text[] := array[
    'upi', 'imps', 'neft', 'rtgs', 'ach', 'nach', 'pos', 'ecom', 'txn', 'ref', 'refno',
    'payment', 'paid', 'pay', 'sent', 'received', 'transfer', 'trf', 'dr', 'cr',
    'to', 'from', 'by', 'via', 'for', 'at', 'on', 'in', 'of', 'the', 'and', 'a', 'an',
    'rs', 'inr', 'bill', 'order'];
  c_max_words constant int := 4;
  v_words text[];
  v_first int;
  v_last  int;
  v_keyword text;
begin
  v_words := string_to_array(nullif(private.normalize_text(p_description), ''), ' ');
  if v_words is null then
    return null;
  end if;

  v_first := 1;
  v_last  := array_length(v_words, 1);

  while v_first <= v_last and v_words[v_first] = any (c_filler) loop
    v_first := v_first + 1;
  end loop;

  v_last := least(v_last, v_first + c_max_words - 1);

  while v_last >= v_first and v_words[v_last] = any (c_filler) loop
    v_last := v_last - 1;
  end loop;

  if v_first > v_last then
    return null;
  end if;

  v_keyword := array_to_string(v_words[v_first:v_last], ' ');
  return case when char_length(v_keyword) >= 2 then v_keyword end;
end;
$$;


-- -----------------------------------------------------------------------------
-- BEFORE INSERT / UPDATE: tidy + auto-categorize
-- -----------------------------------------------------------------------------
create function private.transactions_before_write()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_description text;
  v_category_id uuid;
  v_archived    boolean;
  v_builtin_name  text;
  v_builtin_color text;
begin
  new.description := btrim(coalesce(new.description, ''));

  -- Transfers: no category, ever. Non-transfers: no destination account.
  -- (Clearing rather than rejecting keeps grid edits that change `type`
  -- from failing; the table CHECKs still guard the invariants.)
  if new.type = 'transfer' then
    new.category_id      := null;
    new.auto_categorized := false;
    return new;
  end if;
  new.to_account_id := null;

  -- UPDATE that leaves an existing category untouched: keep it and its flag.
  if tg_op = 'UPDATE'
     and new.category_id is not null
     and new.category_id is not distinct from old.category_id then
    new.auto_categorized := old.auto_categorized;
    return new;
  end if;

  -- Category chosen by the user.
  if new.category_id is not null then
    new.auto_categorized := false;
    return new;
  end if;

  -- category_id is NULL: try to categorize.
  new.auto_categorized := false;
  v_description := private.normalize_text(new.description);
  if v_description = '' then
    return new;
  end if;

  -- 1. Learned rules: longest phrase first, then most-confirmed, then newest.
  select r.category_id
    into v_category_id
  from public.category_rules r
  join public.categories c
    on c.owner_id = r.owner_id and c.id = r.category_id
  where r.owner_id = new.owner_id
    and c.kind = new.type
    and not c.archived
    and strpos(' ' || v_description || ' ', ' ' || r.keyword || ' ') > 0
  order by char_length(r.keyword) desc, r.hit_count desc, r.updated_at desc
  limit 1;

  -- 2. Built-in keyword list, creating the category if the user lacks it.
  if v_category_id is null then
    select m.category_name, m.category_color
      into v_builtin_name, v_builtin_color
    from private.match_builtin_category(new.description, new.type) m;

    if v_builtin_name is not null then
      select c.id, c.archived
        into v_category_id, v_archived
      from public.categories c
      where c.owner_id = new.owner_id
        and c.kind = new.type
        and lower(btrim(c.name)) = lower(v_builtin_name);

      if v_category_id is null then
        insert into public.categories (owner_id, name, kind, color)
        values (new.owner_id, v_builtin_name, new.type, v_builtin_color)
        on conflict do nothing
        returning id into v_category_id;

        -- Lost a race with a concurrent insert of the same category.
        if v_category_id is null then
          select c.id, c.archived
            into v_category_id, v_archived
          from public.categories c
          where c.owner_id = new.owner_id
            and c.kind = new.type
            and lower(btrim(c.name)) = lower(v_builtin_name);
        end if;
      end if;

      if v_archived then
        v_category_id := null;
      end if;
    end if;
  end if;

  -- 3. Nothing matched: stays NULL (Uncategorized).
  if v_category_id is not null then
    new.category_id      := v_category_id;
    new.auto_categorized := true;
  end if;

  return new;
end;
$$;

create trigger transactions_before_write
  before insert or update on public.transactions
  for each row execute function private.transactions_before_write();


-- -----------------------------------------------------------------------------
-- AFTER UPDATE OF category_id: learn from the user's correction
-- -----------------------------------------------------------------------------
create function private.learn_category_rule()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_keyword text;
begin
  v_keyword := private.rule_keyword_from_description(new.description);
  if v_keyword is null then
    return null;
  end if;

  insert into public.category_rules as r (owner_id, keyword, category_id)
  values (new.owner_id, v_keyword, new.category_id)
  on conflict (owner_id, keyword) do update
    set category_id = excluded.category_id,
        hit_count   = case when r.category_id = excluded.category_id then r.hit_count + 1 else 1 end;

  return null;
end;
$$;

-- Fires only for a user-made change: the BEFORE trigger sets
-- auto_categorized = true whenever it chose the category itself.
create trigger transactions_learn_category
  after update of category_id on public.transactions
  for each row
  when (new.category_id is not null
        and new.category_id is distinct from old.category_id
        and not new.auto_categorized)
  execute function private.learn_category_rule();


grant execute on function private.rule_keyword_from_description(text) to authenticated, service_role;
