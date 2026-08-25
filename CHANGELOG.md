# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- A relation with `from` no longer changes every row in the table. The primary key subquery selects
  `table.id` while `from` renames the table it reads, so the database read `table.id` as a reference to the
  row being changed and matched all of them — a whole-table `UPDATE`/`DELETE` from a relation that selected
  a few rows. It raises `ActiveRecord::Returning::Error` now, pointing at `unscope(:from)`.

### Added

- A combination test suite: every relation shape — and combinations of them — run through both
  `update_all_returning` and `delete_all_returning`, asserting the rows the relation selects are the rows
  returned, the rows returned are the rows the database changed, and nothing else moved.

### Notes

- Documented that `delete_all_returning` on a `has_many` deletes rows, while `delete_all` on the same
  association nullifies the foreign key unless it declares `dependent: :delete_all`.

## [0.1.0] - 2026-08-21

Initial release.

### Added

- `ActiveRecord::Relation#update_all_returning(updates, returning: nil)` — runs an `UPDATE ... RETURNING`
  over the current scope and returns the changed rows as an `ActiveRecord::Result`.
- `ActiveRecord::Relation#delete_all_returning(returning: nil)` — the same for `DELETE ... RETURNING`.
- `returning:` accepts a symbol, an array of symbols, `:_all` for `RETURNING *`, or `Arel.sql` for raw SQL.
  It defaults to the primary key, including composite primary keys on Rails 7.1+. `:all` raises, pointing
  at `:_all` — it would be ambiguous with a column named `all` — and so do `:all`/`:_all` inside an array,
  where they would otherwise read as column references.
- Optimistic locking support: the locking column is incremented exactly as `update_all` does, unless the
  caller sets it explicitly.
- Both methods are also delegated onto the model class, like `update_all`, so `User.update_all_returning(...)`
  works and not only `User.where(...).update_all_returning(...)`.
- `ActiveRecord::Returning::Error` and `ActiveRecord::Returning::UnsupportedAdapter`, raised on adapters
  without `RETURNING` support (MySQL, MariaDB, SQLite older than 3.35), on eager-loaded relations, and on
  models without a primary key.

### Notes

- The query cache is cleared after each statement, both thread-wide (as `update_all` does, so a
  primary/replica setup does not keep a stale entry) and on the connection written through. Rails 7.0's
  `exec_query` does not dirty the cache, and its thread-wide clear is itself a no-op under the default
  `legacy_connection_handling`.
- A relation with `group` or `having` raises rather than building a subquery the database rejects, and an
  empty `returning:` list raises instead of emitting a bare `RETURNING`.
- Adapter support prefers `supports_update_returning?` where it exists, falling back to
  `supports_insert_returning?` — with the MySQL family excluded explicitly, because MariaDB answers
  `supports_insert_returning?` with `true` (it has `INSERT ... RETURNING` since 10.5) while having no
  `UPDATE ... RETURNING` at all. CI has a MariaDB lane.
- `alias_attribute` names are resolved in both `updates` and `returning:`, as `update_all` and `pluck` do.
  A returned alias keeps the caller's name: `RETURNING "title" AS "headline"`.
- Active Record is capped at `< 8.2` because rails/rails#57073 proposes an upstream `update_all_returning`
  with a different API. If a relation already defines these methods, the gem leaves them alone and warns.

- PostgreSQL and SQLite 3.35+ only. `ActiveRecord::Returning.supported?` decides, and the notes below
  describe exactly how.
- Both methods are additive: nothing in Active Record is overridden or prepended.
- Callbacks, validations and timestamps are skipped, exactly as with `update_all`/`delete_all`.

[Unreleased]: https://github.com/igorkasyanchuk/activerecord-returning/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/igorkasyanchuk/activerecord-returning/releases/tag/v0.1.0
