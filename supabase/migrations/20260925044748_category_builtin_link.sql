-- =============================================================================
-- Ventrafin — renaming a category keeps auto-categorization pointed at it
-- (Increment 3: both apps can now rename categories)
--
-- Auto-categorization used to find a built-in keyword's category by NAME
-- ('Swiggy' -> the user's category called "Food"). With renaming allowed,
-- renaming "Food" to "Khana" would have made the next Swiggy entry quietly
-- re-create a new "Food" category.
--
-- categories.builtin_name now records which built-in category a row stands
-- for. It is set when the row is created with a built-in name (signup
-- seeding, auto-creation on a keyword match, or the user typing "Fuel") and
-- it is kept when the row is renamed. Clients cannot set or change it: a
-- trigger fills it on insert and preserves it on update (it is cleared only
-- if the category's kind changes).
--
-- Auto-categorization now finds a built-in match's category like this:
--   * through the link first: renamed "Food" -> "Khana", Swiggy still goes
--     to Khana, and no new "Food" appears
--   * else by name, as before: a user category renamed TO a built-in name
--     ("Car costs" -> "Fuel") is used for fuel keywords
--   * an active category beats an archived one: archive "Khana", then add a
--     new "Food", and the new one gets Swiggy
--   * a new category that takes a name whose built-in link another category
--     already holds is just a plain category (the link stays with the
--     renamed original)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Column + backfill (existing rows: the built-in with the same name and kind)
-- -----------------------------------------------------------------------------
alter table public.categories add column builtin_name text;

comment on column public.categories.builtin_name is
  'Built-in category this row stands for (private.builtin_categories.name). Set on insert when the name is a built-in one, kept on rename, so built-in keywords keep finding it. Maintained by trigger; clients cannot set it.';

update public.categories c
   set builtin_name = b.name
  from private.builtin_categories b
 where b.kind = c.kind
   and lower(b.name) = lower(btrim(c.name));

-- At most one category per user and kind stands for each built-in category.
create unique index categories_owner_kind_builtin_key
  on public.categories (owner_id, kind, builtin_name)
  where builtin_name is not null;


-- -----------------------------------------------------------------------------
-- The built-in name for a category name, if it is one. SECURITY DEFINER so it
-- can read the private built-in table; it only returns built-in data.
-- -----------------------------------------------------------------------------
create function private.builtin_category_name(p_name text, p_kind text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select b.name
  from private.builtin_categories b
  where b.kind = p_kind and lower(b.name) = lower(btrim(p_name));
$$;

grant execute on function private.builtin_category_name(text, text) to authenticated, service_role;


-- -----------------------------------------------------------------------------
-- BEFORE INSERT OR UPDATE: maintain the link.
-- SECURITY INVOKER: the "already linked" check reads the caller's own
-- categories under RLS.
-- -----------------------------------------------------------------------------
create function private.categories_builtin_link()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    -- A rename (or any other edit) keeps the link; clients can't change it.
    new.builtin_name := case when new.kind = old.kind then old.builtin_name end;
    return new;
  end if;

  new.builtin_name := private.builtin_category_name(new.name, new.kind);

  -- Another category already stands for this built-in one (the user renamed
  -- it), so this row is just a category that happens to have the name.
  if new.builtin_name is not null and exists (
       select 1
         from public.categories c
        where c.owner_id = new.owner_id
          and c.kind = new.kind
          and c.builtin_name = new.builtin_name) then
    new.builtin_name := null;
  end if;

  return new;
end;
$$;

create trigger categories_builtin_link
  before insert or update on public.categories
  for each row execute function private.categories_builtin_link();


-- -----------------------------------------------------------------------------
-- Which of the user's categories a built-in keyword match should use:
-- active before archived, then the linked row before a same-name one.
-- SECURITY INVOKER, so RLS applies.
-- -----------------------------------------------------------------------------
create function private.builtin_target_category(p_owner_id uuid, p_kind text, p_builtin_name text)
returns table (id uuid, archived boolean)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.id, c.archived
  from public.categories c
  where c.owner_id = p_owner_id
    and c.kind = p_kind
    and (c.builtin_name = p_builtin_name or lower(btrim(c.name)) = lower(p_builtin_name))
  order by c.archived, (c.builtin_name is not distinct from p_builtin_name) desc
  limit 1;
$$;

grant execute on function private.builtin_target_category(uuid, text, text) to authenticated, service_role;


-- -----------------------------------------------------------------------------
-- Auto-categorization: same as 20260924154856_auto_categorization, except that
-- step 2 finds the user's category through private.builtin_target_category.
-- -----------------------------------------------------------------------------
create or replace function private.transactions_before_write()
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
      select t.id, t.archived
        into v_category_id, v_archived
      from private.builtin_target_category(new.owner_id, new.type, v_builtin_name) t;

      if v_category_id is null then
        insert into public.categories (owner_id, name, kind, color)
        values (new.owner_id, v_builtin_name, new.type, v_builtin_color)
        on conflict do nothing
        returning id into v_category_id;

        -- Lost a race with a concurrent insert of the same category.
        if v_category_id is null then
          select t.id, t.archived
            into v_category_id, v_archived
          from private.builtin_target_category(new.owner_id, new.type, v_builtin_name) t;
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
