# frozen_string_literal: true

require "active_support/lazy_load_hooks"

require_relative "returning/version"
require_relative "returning/errors"
require_relative "returning/relation_methods"

module ActiveRecord
  # UPDATE ... RETURNING and DELETE ... RETURNING for ActiveRecord::Relation.
  module Returning
  end
end

# Loading this gem must not boot Active Record.
ActiveSupport.on_load(:active_record) do
  require_relative "returning/statement"

  ActiveRecord::Relation.include(ActiveRecord::Returning::RelationMethods)
end
