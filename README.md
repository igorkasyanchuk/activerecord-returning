# activerecord-returning

`update_all` and `delete_all` tell you *how many* rows changed. This gem tells you **which** ones.

```ruby
User.where(role: :admin).update_all_returning({ role: :member }, returning: %i[id email])
# => #<ActiveRecord::Result @columns=["id", "email"], @rows=[[1, "ada@example.com"], [2, "grace@example.com"]]>

Session.where(expires_at: ..1.week.ago).delete_all_returning(returning: %i[id user_id])
# => #<ActiveRecord::Result @columns=["id", "user_id"], @rows=[[7, 1], [9, 3]]>
```

No second query, no `SELECT ... FOR UPDATE` dance, no race between reading the ids and changing the rows.

PostgreSQL and SQLite 3.35+ have supported `RETURNING` on `UPDATE`/`DELETE` for years. Active Record
exposes it on `insert_all`/`upsert_all` through a `returning:` kwarg, but not on `update_all`/`delete_all` —
still true as of Rails 8.1.

## Installation

```ruby
gem "activerecord-returning"
```

Rails 7.0–8.1, Ruby 3.1+. Nothing to configure: requiring the gem adds two methods to
`ActiveRecord::Relation` and overrides nothing.

## Usage

`update_all_returning` takes `updates` in exactly the shapes `update_all` accepts, plus a `returning:` keyword:

```ruby
User.where(role: :admin).update_all_returning(role: :member)                       # Hash
User.where(role: :admin).update_all_returning("role = 0")                          # String
User.where(role: :admin).update_all_returning(["email = ?", "x@example.com"])      # Array
```

Since both are hashes, a braceless call works too — `returning:` is pulled out of the keywords:

```ruby
User.where(role: :admin).update_all_returning(role: :member, returning: :email)
# same as
User.where(role: :admin).update_all_returning({ role: :member }, returning: :email)
```

(If you genuinely have a column named `returning`, use the braced form.)

### What `returning:` accepts

| Value | Clause |
| --- | --- |
| omitted / `nil` | the primary key (or all of them, for a composite primary key) |
| `:email` | `RETURNING "email"` |
| `%i[id email]` | `RETURNING "id", "email"` |
| `:all` | `RETURNING *` |
| `Arel.sql("id, now() AS at")` | that SQL, verbatim |

A bare `String` is rejected on purpose:

```ruby
User.all.update_all_returning({ role: :member }, returning: "id, email")
# ArgumentError: returning: does not take raw String "id, email". Pass column names as symbols
# (returning: :id, returning: %i[id email]) or wrap SQL in Arel.sql.
```

### The return value

Always an `ActiveRecord::Result` — for both methods, whatever the scope, whatever `returning:` was.

```ruby
result = User.where(role: :admin).update_all_returning({ role: :member }, returning: %i[id email])

result.columns  # => ["id", "email"]
result.rows     # => [[1, "ada@example.com"], [2, "grace@example.com"]]
result.to_a     # => [{"id" => 1, "email" => "ada@example.com"}, ...]
result.length   # => 2
```

Values come back type-cast by the adapter, so a `datetime` column is a `Time`, not a String.

### Getting models back

Ask for every column and hand the rows to `Model.instantiate`:

```ruby
users = User.where(role: :admin)
            .update_all_returning({ role: :member }, returning: :all)
            .map { |attributes| User.instantiate(attributes) }

users.first.email # => "ada@example.com"
```

These are real, non-new records reflecting the post-update row. They have not run any callback.

### Everything a relation can do still works

The statement is built by reducing your relation to a primary-key `SELECT` and using it as a subquery:

```sql
UPDATE "users" SET "role" = 0, "lock_version" = COALESCE("lock_version", 0) + 1
WHERE "users"."id" IN (
  SELECT "users"."id" FROM "users" WHERE "users"."role" = 1 ORDER BY "users"."email" ASC LIMIT 2
)
RETURNING "id", "email"
```

Active Record builds that `SELECT`, so default scopes, `joins`, `limit`, `order`, `merge`, `none`,
association proxies (`user.posts.update_all_returning(...)`) and composite primary keys all work without
this gem knowing anything about them. Composite keys produce `WHERE ("shop_id", "note_id") IN (SELECT ...)`.

The gem uses only public Active Record API — no `Arel::UpdateManager`, no `_substitute_values`, no
`build_arel`. That is why it spans Rails 7.0 through 8.1 with one code path.

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
`UPDATE ... WHERE status = 'pending'` case. Where that matters, take an explicit lock or raise the isolation
level:

```ruby
User.transaction do
  ids = User.where(role: :admin).lock.pluck(:id)
  User.where(id: ids).update_all_returning({ role: :member }, returning: :email)
end
```

**Eager loading is rejected.** An `includes` that turns into a join cannot be reduced to a primary-key
subquery, so it raises `ActiveRecord::Returning::Error`. Use `.joins` instead, or `.unscope(:includes)`.

**Adapters.** Requires `RETURNING` support: PostgreSQL, and SQLite 3.35+ (Rails 7.1+ — the Rails 7.0 SQLite3
adapter has no returning support of its own, so the gem version-checks the database directly there).
MySQL and MariaDB raise `ActiveRecord::Returning::UnsupportedAdapter` — and CI runs the suite against
MySQL to prove it raises rather than doing something surprising. There is no emulation fallback, because a
select-then-update would reintroduce the exact race this gem exists to avoid.

**`returning: :all` on a joined relation** returns the updated table's columns only — `RETURNING *` in an
`UPDATE` refers to the updated row, not the join.

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
| `ActiveRecord::Returning::UnsupportedAdapter` | the adapter cannot do `RETURNING` (MySQL, old SQLite) |
| `ActiveRecord::Returning::Error` | eager loading, or a model with no primary key |
| `ArgumentError` | empty updates, or a bare String in `returning:` |

Both error classes inherit from `ActiveRecord::Returning::Error < StandardError`.

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

PostgreSQL and MySQL connections come from the usual environment variables — `PGHOST`, `PGPORT`,
`PGUSER`, `PGPASSWORD` and `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_USER`, `MYSQL_PASSWORD` — and the
databases are created for you. The test suite uses in-memory SQLite unless `DB` says otherwise.

Against every supported Rails version:

```bash
bundle exec appraisal install
bundle exec appraisal rake test
```

CI runs Ruby 3.1–3.4 across Rails 7.0, 7.1, 7.2, 8.0 and 8.1 on SQLite, plus PostgreSQL (Rails 7.0 and
8.1) and MySQL (Rails 7.1 and 8.1).

## Contributing

Bug reports and pull requests are welcome at
https://github.com/igorkasyanchuk/activerecord-returning.

## License

MIT. Copyright (c) 2026 Igor Kasyanchuk.
