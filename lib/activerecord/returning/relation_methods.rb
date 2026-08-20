# frozen_string_literal: true

module ActiveRecord
  module Returning
    # Mixed into ActiveRecord::Relation. Deliberately holds nothing but the two
    # public methods: every helper lives on Statement so this module can never
    # collide with Active Record's own internals.
    module RelationMethods
      # Runs an UPDATE over the current scope and returns the changed rows.
      #
      #   User.where(role: :admin).update_all_returning({ role: :user }, returning: %i[id email])
      #   # => #<ActiveRecord::Result @columns=["id", "email"], @rows=[[1, "ada@example.com"]]>
      #
      # +updates+ takes the same shapes as #update_all (Hash, String, Array). A
      # braceless hash works too, so `update_all_returning(role: :user, returning: :id)`
      # is the same call. +returning+ defaults to the primary key.
      def update_all_returning(updates = nil, returning: nil, **rest)
        if updates && rest.any?
          raise ArgumentError, "unknown keywords: #{rest.keys.map(&:inspect).join(", ")}"
        end

        Statement.new(self, returning: returning).update(updates || rest)
      end

      # Runs a DELETE over the current scope and returns the deleted rows.
      #
      #   Session.where(expires_at: ..1.week.ago).delete_all_returning(returning: %i[id user_id])
      def delete_all_returning(returning: nil)
        Statement.new(self, returning: returning).delete
      end
    end
  end
end
