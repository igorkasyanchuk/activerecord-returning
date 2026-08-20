# frozen_string_literal: true

module ActiveRecord
  module Returning
    # Base class for every error this gem raises.
    class Error < StandardError; end

    # Raised when the connection's adapter cannot run a RETURNING clause
    # (MySQL, or SQLite older than 3.35).
    class UnsupportedAdapter < Error; end
  end
end
