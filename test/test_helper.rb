# frozen_string_literal: true

require "minitest/autorun"
require_relative "../examples/demo_app"

class ReturningTest < Minitest::Test
  def setup
    DemoApp.seed!
  end

  def composite_primary_keys?
    ActiveRecord::VERSION::STRING >= "7.1"
  end
end
