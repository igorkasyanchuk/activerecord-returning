# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-08-21

Initial release.

### Added

- `ActiveRecord::Relation#update_all_returning(updates, returning: nil)` — runs an `UPDATE ... RETURNING`
  over the current scope and returns the changed rows as an `ActiveRecord::Result`.
- `ActiveRecord::Relation#delete_all_returning(returning: nil)` — the same for `DELETE ... RETURNING`.
- `returning:` accepts a symbol, an array of symbols, `:all` for `RETURNING *`, or `Arel.sql` for raw SQL.
  It defaults to the primary key, including composite primary keys on Rails 7.1+.
- Optimistic locking support: the locking column is incremented exactly as `update_all` does, unless the
  caller sets it explicitly.
- `ActiveRecord::Returning::Error` and `ActiveRecord::Returning::UnsupportedAdapter`, raised on adapters
  without `RETURNING` support (MySQL, MariaDB, SQLite older than 3.35), on eager-loaded relations, and on
  models without a primary key.

### Notes

- PostgreSQL and SQLite 3.35+ only. Adapter support is read from `supports_insert_returning?`, with a
  direct SQLite version check on Rails 7.0, whose SQLite3 adapter predates that method.
- Both methods are additive: nothing in Active Record is overridden or prepended.
- Callbacks, validations and timestamps are skipped, exactly as with `update_all`/`delete_all`.

[Unreleased]: https://github.com/igorkasyanchuk/activerecord-returning/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/igorkasyanchuk/activerecord-returning/releases/tag/v0.1.0
