# frozen_string_literal: true

module ActiveRecord
  module Returning
    # Builds and runs the UPDATE/DELETE ... RETURNING statement for a relation.
    #
    # The relation itself is never rebuilt into Arel by hand. It is reduced to a
    # primary-key SELECT and used as a subquery:
    #
    #   UPDATE "users" SET "role" = 'user'
    #   WHERE "users"."id" IN (SELECT "users"."id" FROM "users" WHERE "users"."role" = 'admin')
    #   RETURNING "id", "email"
    #
    # so default scopes, joins, limit, order, merge, none and composite primary
    # keys all keep working because Active Record builds that SELECT.
    class Statement
      def initialize(relation, returning: nil)
        @relation = relation
        @klass = relation.klass
        @returning = returning
      end

      def update(updates)
        raise ArgumentError, "Empty list of attributes to change" if updates.blank?

        run("Update All Returning") do |conn|
          "UPDATE #{quoted_table_name(conn)} SET #{set_clause(conn, updates)} " \
            "WHERE #{where_clause(conn)} RETURNING #{returning_clause(conn)}"
        end
      end

      def delete
        run("Delete All Returning") do |conn|
          "DELETE FROM #{quoted_table_name(conn)} " \
            "WHERE #{where_clause(conn)} RETURNING #{returning_clause(conn)}"
        end
      end

      private
        attr_reader :relation, :klass, :returning

        def run(name)
          with_connection do |conn|
            validate!(conn)
            result = conn.exec_query(yield(conn), name)

            clear_query_caches(conn)
            relation.reset # loaded records are stale now
            result
          end
        end

        # exec_query only dirties the query cache from Rails 7.1 on, and a cached
        # SELECT of a row we just changed is stale.
        #
        # Both clears are deliberate. The thread-wide one is what update_all uses,
        # and is the one that matters for a primary/replica setup, where the stale
        # entry can sit in another pool. It is also a no-op on Rails 7.0 with the
        # default legacy_connection_handling, where it walks connection_handlers
        # and misses the handler actually in use — Rails 7.0's own update_all
        # leaves the cache stale for the same reason. So the connection we wrote
        # through is cleared directly as well.
        def clear_query_caches(conn)
          ActiveRecord::Base.clear_query_caches_for_current_thread if
            ActiveRecord::Base.respond_to?(:clear_query_caches_for_current_thread)

          conn.clear_query_cache
        end

        # Rails 7.2 deprecated holding on to a connection via klass.connection.
        def with_connection(&block)
          if klass.respond_to?(:with_connection)
            klass.with_connection(&block)
          else
            block.call(klass.connection)
          end
        end

        def validate!(conn)
          unless Returning.supported?(conn)
            raise UnsupportedAdapter,
              "the #{conn.adapter_name} adapter does not support RETURNING on UPDATE/DELETE"
          end

          if relation.eager_loading?
            raise Error,
              "#{self.class.name} cannot be used with eager loading, because an `includes` that " \
              "becomes a join cannot be reduced to a primary key subquery. Use `.joins` instead, " \
              "or `.unscope(:includes)`."
          end

          raise Error, "#{klass.name} has no primary key, so there is nothing to match rows on" if primary_keys.empty?

          unless relation.from_clause.empty?
            raise Error,
              "#{self.class.name} cannot be used with `from`, because the primary key subquery selects " \
              "#{primary_keys.map { |name| "#{klass.table_name}.#{name}" }.join(", ")} while `from` renames " \
              "the table it reads. " \
              "The database then reads that as a reference to the row being changed and matches every " \
              "row in the table. Use `.unscope(:from)`."
          end

          if relation.group_values.any? || !relation.having_clause.empty?
            raise Error,
              "#{self.class.name} cannot be used with group or having: the primary key subquery would " \
              "select a column that is not grouped. Reduce the relation to plain conditions first, for " \
              "example with `where(id: grouped_relation.select(:id))`."
          end
        end

        def set_clause(conn, updates)
          set = klass.sanitize_sql_for_assignment(resolve_aliases(updates))
          set += ", #{increment_lock_version(conn)}" if increment_lock_version?(updates)
          set
        end

        # alias_attribute names are not columns, so they have to be resolved
        # before the SET clause is built. update_all does the same.
        def resolve_aliases(updates)
          return updates unless updates.is_a?(Hash) && klass.attribute_aliases.any?

          updates.transform_keys { |key| klass.attribute_aliases[key.to_s] || key }
        end

        # Matches update_all: bump the lock column unless the caller set it.
        def increment_lock_version?(updates)
          return false unless klass.locking_enabled?
          return false unless updates.is_a?(Hash)

          updates = resolve_aliases(updates)

          column = klass.locking_column
          !updates.key?(column) && !updates.key?(column.to_sym)
        end

        def increment_lock_version(conn)
          column = conn.quote_column_name(klass.locking_column)
          "#{column} = COALESCE(#{column}, 0) + 1"
        end

        def where_clause(conn)
          columns = primary_keys.map { |name| "#{quoted_table_name(conn)}.#{conn.quote_column_name(name)}" }
          left = columns.one? ? columns.first : "(#{columns.join(", ")})"

          "#{left} IN (#{subquery_sql})"
        end

        # Arel attributes, not bare symbols, so the primary key stays
        # table-qualified and cannot go ambiguous under a join.
        def subquery_sql
          attributes = primary_keys.map { |name| klass.arel_table[name] }
          relation.unscope(:select).select(*attributes).to_sql
        end

        def returning_clause(conn)
          case returning
          when nil then primary_keys.map { |name| conn.quote_column_name(name) }.join(", ")
          when false
            raise ArgumentError,
              "returning: false is not supported, because these methods always return rows. " \
              "Use update_all/delete_all if you only want the count."
          when :_all then "*"
          when :all
            raise ArgumentError,
              "returning: :all is ambiguous with a column named \"all\". Use returning: :_all for " \
              "RETURNING *, or Arel.sql('\"all\"') for the column."
          else
            columns = Array(returning)
            raise ArgumentError, "returning: is empty, so there is nothing to return" if columns.empty?

            columns.map { |column| returning_column(conn, column) }.join(", ")
          end
        end

        def returning_column(conn, column)
          # SqlLiteral is a String subclass, so it has to be checked first.
          case column
          when Arel::Nodes::SqlLiteral then column.to_s
          when Symbol then returning_attribute(conn, column)
          when String
            raise ArgumentError,
              "returning: does not take raw String #{column.inspect}. Pass column names as symbols " \
              "(returning: :id, returning: %i[id email]) or wrap SQL in Arel.sql."
          else
            raise ArgumentError, "unsupported returning: value #{column.inspect}"
          end
        end

        # An alias_attribute is not a column, so it has to be resolved — and then
        # aliased back, so the caller reads the result under the name they asked
        # for: RETURNING "title" AS "headline".
        def returning_attribute(conn, name)
          column = klass.attribute_aliases[name.to_s]
          return conn.quote_column_name(name) if column.nil?

          "#{conn.quote_column_name(column)} AS #{conn.quote_column_name(name)}"
        end

        def primary_keys
          @primary_keys ||= Array(klass.primary_key)
        end

        def quoted_table_name(conn)
          conn.quote_table_name(klass.table_name)
        end
    end
  end
end
