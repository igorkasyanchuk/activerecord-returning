# frozen_string_literal: true

require "minitest/autorun"

# The suite runs on in-memory SQLite by default. DB=postgres or DB=mysql point
# it at a real server; see .github/workflows/ci.yml for the environment those
# expect.
ENV["AR_RETURNING_DATABASE"] ||=
  ENV.fetch("DB", "sqlite") == "sqlite" ? ":memory:" : "activerecord_returning_test"

require_relative "../dev/boot"

Dev.connect!
Dev.load_schema!
Dev.load_models!

class ReturningTest < Minitest::Test
  def setup
    skip "#{Dev::ADAPTER} does not support RETURNING" unless Dev.returning_supported?

    Dev.seed!
  end

  def composite_primary_keys?
    ActiveRecord::VERSION::STRING >= "7.1"
  end
end
