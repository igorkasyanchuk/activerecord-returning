# frozen_string_literal: true

require "active_support/lazy_load_hooks"

require_relative "returning/version"
require_relative "returning/errors"
require_relative "returning/relation_methods"
require_relative "returning/querying"

module ActiveRecord
  # UPDATE ... RETURNING and DELETE ... RETURNING for ActiveRecord::Relation.
  module Returning
    # Can this connection run UPDATE/DELETE ... RETURNING?
    #
    # supports_update_returning? is the precise question, but it only exists on
    # newer Rails. supports_insert_returning? is the closest stand-in, with one
    # trap: MariaDB answers true to it (it has INSERT ... RETURNING since 10.5)
    # while having no UPDATE ... RETURNING at all, so the MySQL family is ruled
    # out explicitly.
    #
    # The SQLite branch is for Rails 7.0, whose SQLite3 adapter predates the
    # capability methods even though the database itself supports RETURNING.
    # Version compares itself to a version string by parts; a plain string
    # compare would read "3.4.0" as newer than "3.35.0".
    def self.supported?(connection)
      return connection.supports_update_returning? if connection.respond_to?(:supports_update_returning?)

      adapter = connection.adapter_name.to_s
      return false if adapter.match?(/mysql|trilogy|mariadb/i)
      return true if connection.supports_insert_returning?

      adapter.match?(/sqlite/i) && connection.database_version >= "3.35.0"
    end
  end
end

# Loading this gem must not boot Active Record.
ActiveSupport.on_load(:active_record) do
  require_relative "returning/statement"

  # Active Record may grow its own update_all_returning one day (rails/rails#57073
  # proposes one with a different API: columns via select(), defaulting to all of
  # them). An include cannot override a method defined on Relation itself, so
  # rather than silently doing nothing, say so.
  taken = %i[update_all_returning delete_all_returning].select do |name|
    ActiveRecord::Relation.method_defined?(name)
  end

  if taken.any?
    warn "[activerecord-returning] ActiveRecord::Relation already defines #{taken.join(" and ")}. " \
         "Leaving #{taken.one? ? "that one" : "them"} alone. Note that Active Record's own version " \
         "selects columns with select(), not with returning:."
  end

  # Add only the names Active Record has not taken, so one upstream method does
  # not silently remove the other.
  without_taken = lambda do |mixin|
    next mixin if taken.empty?

    mixin.dup.tap { |copy| taken.each { |name| copy.send(:remove_method, name) } }
  end

  ActiveRecord::Relation.include(without_taken.call(ActiveRecord::Returning::RelationMethods))
  ActiveRecord::Base.extend(without_taken.call(ActiveRecord::Returning::Querying))
end
