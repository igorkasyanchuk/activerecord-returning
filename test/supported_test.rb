# frozen_string_literal: true

require "test_helper"

# ActiveRecord::Returning.supported? decides whether a statement is built at all,
# and getting it wrong means either a raw SQL syntax error from the database or a
# refusal to run on an adapter that would have worked. These exercise it against
# stand-in connections, so the MariaDB and old-SQLite answers are covered without
# needing those servers.
class SupportedTest < Minitest::Test
  Version = ActiveRecord::ConnectionAdapters::AbstractAdapter::Version

  # Nothing but what supported? actually asks for.
  class FakeConnection
    def initialize(adapter_name:, insert_returning:, version: "1.0.0")
      @adapter_name = adapter_name
      @insert_returning = insert_returning
      @version = version
    end

    attr_reader :adapter_name

    def supports_insert_returning? = @insert_returning
    def database_version = Version.new(@version)
  end

  class ConnectionWithUpdateReturning < FakeConnection
    def initialize(update_returning:, **options)
      super(**options)
      @update_returning = update_returning
    end

    def supports_update_returning? = @update_returning
  end

  def supported?(**options) = ActiveRecord::Returning.supported?(FakeConnection.new(**options))

  def test_postgresql
    assert supported?(adapter_name: "PostgreSQL", insert_returning: true)
  end

  def test_mariadb_claiming_insert_returning_is_still_unsupported
    # MariaDB 10.5+ has INSERT ... RETURNING, so the adapter answers true, but
    # there is no UPDATE ... RETURNING and the statement would be a syntax error.
    refute supported?(adapter_name: "Trilogy", insert_returning: true, version: "11.8.0")
    refute supported?(adapter_name: "Mysql2", insert_returning: true, version: "10.5.0")
  end

  def test_mysql
    refute supported?(adapter_name: "Mysql2", insert_returning: false, version: "8.0.0")
  end

  def test_sqlite_new_enough_without_the_capability_method
    assert supported?(adapter_name: "SQLite", insert_returning: false, version: "3.35.0")
    assert supported?(adapter_name: "SQLite", insert_returning: false, version: "3.45.2")
  end

  def test_sqlite_too_old
    refute supported?(adapter_name: "SQLite", insert_returning: false, version: "3.34.1")
  end

  def test_sqlite_version_is_compared_by_parts_not_as_a_string
    # "3.9.0" > "3.35.0" as strings, which would let RETURNING through on a
    # database that has never heard of it.
    refute supported?(adapter_name: "SQLite", insert_returning: false, version: "3.9.0")
    refute supported?(adapter_name: "SQLite", insert_returning: false, version: "3.4.0")
  end

  def test_supports_update_returning_wins_when_the_adapter_has_it
    yes = ConnectionWithUpdateReturning.new(adapter_name: "PostgreSQL", insert_returning: false, update_returning: true)
    no = ConnectionWithUpdateReturning.new(adapter_name: "PostgreSQL", insert_returning: true, update_returning: false)

    assert ActiveRecord::Returning.supported?(yes)
    refute ActiveRecord::Returning.supported?(no)
  end

  def test_the_real_connection_agrees_with_the_suite
    expected = Dev.returning_supported?

    ActiveRecord::Base.connection_pool.with_connection do |conn|
      assert_equal expected, ActiveRecord::Returning.supported?(conn)
    end
  end
end
