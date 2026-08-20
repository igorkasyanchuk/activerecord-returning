# frozen_string_literal: true

require "minitest/autorun"

# Pure Ruby, so the expectation itself does not depend on the gem being loaded
# by some other test file first.
require_relative "../lib/activerecord/returning/version"

# Requiring the gem must not need Active Record — or Active Support's core
# extensions — to already be loaded, and must not boot Active Record itself.
class LoadTest < Minitest::Test
  def test_requiring_the_gem_on_its_own
    lib = File.expand_path("../lib", __dir__)
    script = "require 'activerecord-returning'; " \
             "print defined?(ActiveRecord::Base) ? 'ActiveRecord booted' : ActiveRecord::Returning::VERSION"

    output = IO.popen([RbConfig.ruby, "-I", lib, "-e", script], err: %i[child out], &:read)

    assert_equal ActiveRecord::Returning::VERSION, output
  end
end
