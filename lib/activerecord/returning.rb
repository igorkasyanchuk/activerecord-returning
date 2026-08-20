# frozen_string_literal: true

require "active_support/lazy_load_hooks"

require_relative "returning/version"
require_relative "returning/errors"
require_relative "returning/relation_methods"
require_relative "returning/querying"

module ActiveRecord
  # UPDATE ... RETURNING and DELETE ... RETURNING for ActiveRecord::Relation.
  module Returning
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
         "Leaving them alone: the gem is doing nothing and can be removed. Note that Active Record's " \
         "own version selects columns with select(), not with returning:."
  else
    ActiveRecord::Relation.include(ActiveRecord::Returning::RelationMethods)
    ActiveRecord::Base.extend(ActiveRecord::Returning::Querying)
  end
end
