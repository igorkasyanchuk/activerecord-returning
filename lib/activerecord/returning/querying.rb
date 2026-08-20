# frozen_string_literal: true

# delegate is an Active Support core extension, and this file is loaded before
# Active Record boots.
require "active_support/core_ext/module/delegation"

module ActiveRecord
  module Returning
    # Extended into ActiveRecord::Base, so the methods can be called on the model
    # itself and not only on a relation — the same delegation Rails uses to put
    # update_all and delete_all on the class.
    #
    #   User.update_all_returning(role: :member)
    module Querying
      delegate :update_all_returning, :delete_all_returning, to: :all
    end
  end
end
