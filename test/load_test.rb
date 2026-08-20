# frozen_string_literal: true

require "minitest/autorun"

# Requiring the gem must not need Active Record, or Active Support's core
# extensions, to be loaded already.
class LoadTest < Minitest::Test
  def test_requiring_the_gem_on_its_own
    lib = File.expand_path("../lib", __dir__)
    script = "require 'activerecord-returning'; " \
             "raise 'ActiveRecord booted' if defined?(ActiveRecord::Base); " \
             "print ActiveRecord::Returning::VERSION"

    output = IO.popen([RbConfig.ruby, "--disable-gems", "-I", lib, "-e", script], err: %i[child out], &:read)

    assert_equal ActiveRecord::Returning::VERSION, output, "requiring the gem alone failed: #{output}"
  end
end
