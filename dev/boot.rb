# frozen_string_literal: true

# Development sandbox and shared database setup.
#
#   bin/setup      create the database, load the schema, seed it
#   bin/console    IRB with all of it loaded
#
# Pick the backend with DB=sqlite (default), DB=postgres or DB=mysql. The test
# suite uses this same file, with its own database name.

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "active_record"
require "activerecord-returning"
require "logger"

module Dev
  ADAPTER = ENV.fetch("DB", "sqlite")
  ROOT = File.expand_path("..", __dir__)
  DATABASE = ENV.fetch("AR_RETURNING_DATABASE", "activerecord_returning_dev")

  module_function

  # +database+ is a database name, or ":memory:" / a path for SQLite.
  def config(database = DATABASE)
    case ADAPTER
    when "sqlite"
      { adapter: "sqlite3", database: database.start_with?(":") ? database : sqlite_path(database) }
    when "postgres"
      {
        adapter: "postgresql",
        host: ENV["PGHOST"],
        port: ENV["PGPORT"],
        username: ENV.fetch("PGUSER", "postgres"),
        password: ENV["PGPASSWORD"],
        database: database,
        encoding: "utf8"
      }.compact
    when "mysql", "mariadb"
      {
        adapter: "trilogy",
        host: ENV.fetch("MYSQL_HOST", "127.0.0.1"),
        port: ENV.fetch("MYSQL_PORT", ADAPTER == "mariadb" ? 3307 : 3306).to_i,
        username: ENV.fetch("MYSQL_USER", "root"),
        password: ENV["MYSQL_PASSWORD"],
        database: database,
        encoding: "utf8mb4"
      }.compact
    else
      raise ArgumentError, "unknown DB=#{ADAPTER} (sqlite, postgres, mysql, mariadb)"
    end
  end

  def sqlite_path(database)
    File.join(ROOT, "dev", "#{database}.sqlite3")
  end

  # Creates the database when the adapter needs one, then connects.
  def connect!(database = DATABASE)
    create_database!(database) unless ADAPTER == "sqlite"
    ActiveRecord::Base.establish_connection(config(database))
  end

  def create_database!(database)
    ActiveRecord::Base.establish_connection(config(bootstrap_database))
    ActiveRecord::Base.connection.create_database(database)
  rescue ActiveRecord::DatabaseAlreadyExists, ActiveRecord::StatementInvalid
    nil
  ensure
    ActiveRecord::Base.connection_handler.clear_all_connections!
  end

  # A database that always exists, used only to CREATE the real one.
  def bootstrap_database
    ADAPTER == "postgres" ? "postgres" : "mysql"
  end

  # load, not require, so reset! really does reload the schema each time.
  def load_schema!
    load File.expand_path("schema.rb", __dir__)
  end

  def load_models!
    require_relative "models"
  end

  def seed!
    load File.expand_path("seeds.rb", __dir__)
    Seeds.run
  end

  # Load the schema, then re-seed. Safe to call again at any time.
  def reset!(database = DATABASE)
    connect!(database)
    load_schema!
    load_models!
    seed!
  end

  def ready?
    ActiveRecord::Base.connection.table_exists?(:users)
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
    false
  end

  # Exactly the question the gem itself asks, so the suite can never decide to
  # skip on a connection the gem would have run on, or the other way round.
  def returning_supported?
    ActiveRecord::Base.connection_pool.with_connection { |conn| ActiveRecord::Returning.supported?(conn) }
  end

  def describe
    ADAPTER == "sqlite" ? "sqlite3 #{sqlite_path(DATABASE)}" : "#{ADAPTER} database #{DATABASE}"
  end

  def counts
    [User, Post, Session].to_h { |model| [model.table_name.to_sym, model.count] }
  end

  # Echo every statement to stdout. On by default in bin/console.
  def log!(enabled = true)
    ActiveRecord::Base.logger = enabled ? Logger.new($stdout, formatter: ->(_, _, _, msg) { "#{msg}\n" }) : nil
    enabled
  end
end
