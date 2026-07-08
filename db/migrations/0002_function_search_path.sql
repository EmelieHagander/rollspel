-- ============================================================================
-- 0002_function_search_path.sql
--
-- Hardens the two rpg helper functions against role-mutable search_path
-- (post-apply security advisor WARN: function_search_path_mutable on
-- rpg.ability_modifier and rpg.set_updated_at).
--
-- Choice: SET search_path = '' (empty), the strictest option, over
-- 'pg_catalog'. Rationale: pg_catalog is ALWAYS searched implicitly before
-- any configured path, so an empty path still resolves every built-in these
-- functions use while guaranteeing that nothing else — no tenant schema, no
-- attacker-created object — can ever be resolved unqualified inside them.
--
-- Verified safe per function body (0001):
--   * rpg.ability_modifier(integer) — pure SQL: floor(), numeric operators,
--     an ::integer cast. All pg_catalog. No table or schema-dependent
--     reference anywhere in the body.
--   * rpg.set_updated_at() — plpgsql trigger: assigns now() (pg_catalog) to
--     NEW.updated_at (a record variable, no catalog lookup). No table or
--     schema-dependent reference anywhere in the body.
--
-- Scope fence note: the advisor raises the same WARN on akr.* functions.
-- Those belong to another tenant, outside schema rpg, and are deliberately
-- NOT touched here — the fence has no exceptions.
--
-- Forward-only: 0001 is applied history; this hardening lands as a new
-- migration, never as an edit to 0001.
-- ============================================================================

begin;

alter function rpg.ability_modifier(integer) set search_path = '';

alter function rpg.set_updated_at() set search_path = '';

commit;
