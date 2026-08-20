# activerecord-returning

[![Gem Version](https://badge.fury.io/rb/activerecord-returning.svg)](https://rubygems.org/gems/activerecord-returning)
[![CI](https://github.com/igorkasyanchuk/activerecord-returning/actions/workflows/ci.yml/badge.svg)](https://github.com/igorkasyanchuk/activerecord-returning/actions/workflows/ci.yml)

`update_all` and `delete_all` tell you **how many** rows changed. This gem tells you **which** ones.

```ruby
User.where(role: :admin).update_all_returning({ role: :member }, returning: %i[id email])
# => #<ActiveRecord::Result @columns=["id", "email"],
#                           @rows=[[1, "ada@example.com"], [2, "grace@example.com"]]>

Session.where(expires_at: ..1.week.ago).delete_all_returning(returning: %i[id user_id])
# => #<ActiveRecord::Result @columns=["id", "user_id"], @rows=[[7, 1], [9, 3]]>
```

One statement. No second query, no `SELECT ... FOR UPDATE` dance, no window between deciding which rows to
change and changing them.

## The problem

You expire sessions, flip a batch of records, sweep old rows — and then you need to know what you touched,
to enqueue jobs, send mail, or write an audit log. `update_all` gives you an Integer, so the usual answers are:

```ruby
# Racy: another process can change the set between the two statements.
ids = Session.where(expires_at: ..1.week.ago).pluck(:id)
Session.where(id: ids).delete_all

# Correct, but two round trips, a transaction and a lock you have to remember.
Session.transaction do
  ids = Session.where(expires_at: ..1.week.ago).lock.pluck(:id)
  Session.where(id: ids).delete_all
  ids
end
```

PostgreSQL and SQLite 3.35+ have supported a `RETURNING` clause on `UPDATE` and `DELETE` for years — one
statement that changes the rows and hands them back. Active Record exposes it on `insert_all`/`upsert_all`
through a `returning:` kwarg, but not on `update_all`/`delete_all`. It has been proposed upstream several
times and, as of Rails 8.1, still hasn't landed. This gem adds the two methods, using only public
Active Record API.

## Installation

```ruby
# Gemfile
gem "activerecord-returning"
```

```bash
bundle install
```

Nothing to configure and nothing to initialize. Requiring the gem adds two methods to
`ActiveRecord::Relation` and overrides nothing — no `prepend`, no patched `update_all`.

## Database support

| Database | `update_all_returning` | `delete_all_returning` |
| --- | --- | --- |
| PostgreSQL (all supported versions) | yes | yes |
| SQLite 3.35+ (Rails 7.1+; see note) | yes | yes |
| MySQL | no — raises `UnsupportedAdapter` | no — raises `UnsupportedAdapter` |
| MariaDB | no — raises `UnsupportedAdapter` | no — raises `UnsupportedAdapter` |

Support is decided by the adapter's own `supports_insert_returning?`, so it tracks what your database can
actually do rather than a hardcoded list. The one exception: the Rails 7.0 SQLite3 adapter predates that
capability method, so on Rails 7.0 the gem checks the SQLite version (3.35+) directly.

**MySQL has no `RETURNING`** — on any statement. MariaDB has it for `INSERT` (10.5+) and `DELETE` (10.0+),
but not for `UPDATE`, and neither the `mysql2` nor the `trilogy` adapter reports returning support. There is
no SQL for this gem to generate, so it raises loudly instead of guessing:

```ruby
User.where(role: :admin).update_all_returning(role: :member)
# ActiveRecord::Returning::UnsupportedAdapter:
#   the Trilogy adapter does not support RETURNING on UPDATE/DELETE
```

On MySQL, do it in two statements with a lock, inside a transaction:

```ruby
User.transaction do
  ids = User.where(role: :admin).lock.pluck(:id)   # SELECT ... FOR UPDATE
  User.where(id: ids).update_all(role: :member)
  User.where(id: ids)                              # the rows you changed
end
```

The gem deliberately does not do that for you. It is only correct inside a transaction with a lock, and
hiding those requirements behind a method that looks atomic would hand a race to every caller who forgets.

## Usage

### `update_all_returning`

Takes `updates` in exactly the shapes `update_all` accepts, plus a `returning:` keyword:

```ruby
User.where(role: :admin).update_all_returning(role: :member)                   # Hash
User.where(role: :admin).update_all_returning("role = 0")                      # String
User.where(role: :admin).update_all_returning(["email = ?", "x@example.com"])  # Array
```

Hash values are cast through the attribute's type, exactly as `update_all` does, so enums, symbols,
booleans and JSON columns behave identically:

```ruby
User.where(id: 1).update_all_returning(role: :admin)     # enum -> 1
Post.where(id: 1).update_all_returning(published: true)  # boolean -> adapter's true
```

Since both arguments are hashes, a braceless call works too — `returning:` is pulled out of the keywords:

```ruby
User.where(role: :admin).update_all_returning(role: :member, returning: :email)
# same as
User.where(role: :admin).update_all_returning({ role: :member }, returning: :email)
```

(If you genuinely have a column named `returning`, use the braced form.)

### `delete_all_returning`

```ruby
Session.where(expires_at: ..1.week.ago).delete_all_returning
Session.where(expires_at: ..1.week.ago).delete_all_returning(returning: %i[id user_id])
```

### What `returning:` accepts

| Value | Clause |
| --- | --- |
| omitted / `nil` | the primary key (all of them, for a composite primary key) |
| `:email` | `RETURNING "email"` |
| `%i[id email]` | `RETURNING "id", "email"` |
| `:all` | `RETURNING *` |
| `Arel.sql("id, now() AS at")` | that SQL, verbatim |

A bare `String` is rejected on purpose — it would be raw SQL from a value that is often user input:

```ruby
User.all.update_all_returning({ role: :member }, returning: "id, email")
# ArgumentError: returning: does not take raw String "id, email". Pass column names as symbols
# (returning: :id, returning: %i[id email]) or wrap SQL in Arel.sql.
```

`returning: false` raises too — these methods always return rows. Use plain `update_all`/`delete_all` when
you only want the count.

## The return value

Always an `ActiveRecord::Result` — for both methods, whatever the scope, whatever `returning:` was. It is
the same plain `ActiveRecord::Result` Rails hands back from `insert_all`, not a wrapper or a subclass.

```ruby
result = User.where(role: :admin).update_all_returning({ role: :member }, returning: %i[id email])

result.columns  # => ["id", "email"]
result.rows     # => [[1, "ada@example.com"], [2, "grace@example.com"]]
result.to_a     # => [{"id" => 1, "email" => "ada@example.com"}, ...]
result.length   # => 2
result.each { |row| AuditLog.record(row["id"]) }
```

Values come back type-cast by the adapter, so a `datetime` column is a `Time` and a `jsonb` column is a
Hash, not a String.

### Getting models back

Ask for every column and hand the rows to `Model.instantiate`:

```ruby
users = User.where(role: :admin)
            .update_all_returning({ role: :member }, returning: :all)
            .map { |attributes| User.instantiate(attributes) }

users.first.email       # => "ada@example.com"
users.first.new_record? # => false
```

These are real, persisted records reflecting the post-update row. No callback has run on them. The gem
doesn't do this for you — the point of a `Result` is that you decide what the rows cost.

## Everything a relation can do still works

The statement is built by reducing your relation to a primary-key `SELECT` and using it as a subquery:

```sql
UPDATE "users" SET "role" = 0, "lock_version" = COALESCE("lock_version", 0) + 1
WHERE "users"."id" IN (
  SELECT "users"."id" FROM "users" WHERE "users"."role" = 1 ORDER BY "users"."email" ASC LIMIT 2
)
RETURNING "id", "email"
```

Active Record builds that inner `SELECT`, which means default scopes, `joins`, `where`, `limit`, `order`,
`merge`, `none`, association proxies and composite primary keys all work without this gem knowing anything
about them:

```ruby
User.joins(:posts).where(posts: { published: true }).update_all_returning(role: :member)
User.order(:created_at).limit(100).update_all_returning({ role: :member }, returning: :id)
user.posts.update_all_returning({ published: true }, returning: :id)
Note.where(shop_id: 1).delete_all_returning   # WHERE ("shop_id", "note_id") IN (SELECT ...)
```

No `Arel::UpdateManager`, no `_substitute_values`, no `build_arel` — nothing private. That is why one code
path covers Rails 7.0 through 8.1.

### Optimistic locking

Handled exactly like `update_all`: if the model has a locking column and you did not set it yourself,
`lock_version = COALESCE(lock_version, 0) + 1` is appended. Set it explicitly and your value wins.

## Caveats

**Callbacks, validations and timestamps are skipped**, exactly as with `update_all`/`delete_all`. Nothing is
instantiated. In particular `updated_at` is *not* touched — pass it yourself if you want it:

```ruby
User.where(role: :admin).update_all_returning(role: :member, updated_at: Time.current)
```

**Isolation.** The subquery is evaluated inside the same statement, so there is no separate read and no
window between "pick the rows" and "change them". But under `READ COMMITTED` (PostgreSQL's default) a row
whose value changed after the statement's snapshot can still be re-read and updated — the classic
`UPDATE ... WHERE status = 'pending'` case. Where that matters, take an explicit lock or raise the
isolation level:

```ruby
User.transaction do
  ids = User.where(role: :admin).lock.pluck(:id)
  User.where(id: ids).update_all_returning({ role: :member }, returning: :email)
end
```

**Eager loading is rejected.** An `includes` that turns into a join cannot be reduced to a primary-key
subquery, so it raises `ActiveRecord::Returning::Error`. Use `.joins` instead, or `.unscope(:includes)`.

**`returning: :all` on a joined relation** returns the updated table's columns only — `RETURNING *` in an
`UPDATE` refers to the updated row, not to the join.

## Compared to `insert_all` / `upsert_all`

The return type and the default are identical to the `returning:` kwarg Rails already ships on
`insert_all`/`upsert_all`: an `ActiveRecord::Result`, defaulting to the primary key. Three differences:

- `returning: :all` is an addition here. Rails quotes `:all` as a column named `all`.
- `returning: false` raises instead of returning an empty Result.
- On MySQL, Rails returns an empty Result; this gem raises `UnsupportedAdapter`, because an empty Result is
  indistinguishable from "nothing matched".

## Why methods instead of a chainable `.returning`

`User.returning(:id).where(...).update_all(...)` was considered and deliberately rejected:

1. It would make `update_all` return an Integer *or* a Result depending on state possibly set in another
   file. The call site stops being readable and the type stops being checkable.
2. It needs `prepend` over `update_all`/`delete_all`. Removing the gem would then silently change the
   behaviour of working code, instead of raising `NoMethodError` at the one place that used it.
3. Rails put `returning:` on `insert_all`/`upsert_all` as a keyword argument, not a query method. Matching
   that precedent keeps the migration path open if `update_all(returning:)` ever lands upstream.

The trade-off: a chainable form would let you bake it into a scope
(`scope :expiring, -> { where(...).returning(:id) }`). That is not supported, and won't be.

## Errors

| Error | When |
| --- | --- |
| `ActiveRecord::Returning::UnsupportedAdapter` | the adapter cannot do `RETURNING` (MySQL, MariaDB, SQLite < 3.35) |
| `ActiveRecord::Returning::Error` | eager loading, or a model with no primary key |
| `ArgumentError` | empty updates, a bare String in `returning:`, or `returning: false` |

`UnsupportedAdapter` inherits from `ActiveRecord::Returning::Error`, which inherits from `StandardError`.

## Requirements

- Ruby 3.1+
- Active Record 7.0 – 8.1
- PostgreSQL, or SQLite 3.35+

CI runs Ruby 3.1–3.4 against Rails 7.0, 7.1, 7.2, 8.0 and 8.1 on SQLite, plus PostgreSQL (Rails 7.0 and 8.1)
and MySQL (Rails 7.1 and 8.1). The dependency range in the gemspec is exactly the range that matrix
exercises — `to_sql` output shifts subtly between versions, and that matrix is what catches it.

## Development

```bash
bin/setup                 # create the dev database, load the schema, seed it
bin/console               # IRB with User, Post, Session, Note (composite PK), Legacy (no PK)
bundle exec rake test
```

Everything above takes `DB=sqlite` (default, a file under `dev/`), `DB=postgres` or `DB=mysql`:

```bash
DB=postgres bin/setup && DB=postgres bin/console
DB=postgres bundle exec rake test
DB=mysql    bundle exec rake test   # only the UnsupportedAdapter tests run here
```

Connections come from the usual environment variables — `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` and
`MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_USER`, `MYSQL_PASSWORD` — and the databases are created for you. The test
suite uses in-memory SQLite unless `DB` says otherwise.

Against every supported Rails version:

```bash
bundle exec appraisal install
bundle exec appraisal rake test
```

### Releasing

```bash
# 1. bump lib/activerecord/returning/version.rb
# 2. move the Unreleased entries in CHANGELOG.md under the new version
bundle exec rake release   # tags vX.Y.Z, pushes the tag, pushes the gem to RubyGems
```

## Contributing

Bug reports and pull requests are welcome at
https://github.com/igorkasyanchuk/activerecord-returning.

## License

MIT. Copyright (c) 2026 Igor Kasyanchuk.
