# frozen_string_literal: true

require "test_helper"

# The other tests skip on an adapter without RETURNING. These are the ones that
# only make sense there: MySQL must fail loudly, not silently do something else.
class UnsupportedAdapterTest < Minitest::Test
  def setup
    skip "#{Dev::ADAPTER} supports RETURNING" if Dev.returning_supported?

    Dev.seed!
  end

  def test_update_all_returning_raises
    error = assert_raises(ActiveRecord::Returning::UnsupportedAdapter) do
      User.where(role: :admin).update_all_returning(role: :member)
    end

    assert_match(/RETURNING/, error.message)
    assert_equal 2, User.where(role: :admin).count, "nothing should have been updated"
  end

  def test_delete_all_returning_raises
    assert_raises(ActiveRecord::Returning::UnsupportedAdapter) { Session.all.delete_all_returning }

    assert_equal 3, Session.count
  end

  def test_the_error_names_the_adapter
    error = assert_raises(ActiveRecord::Returning::UnsupportedAdapter) { User.all.delete_all_returning }

    assert_match(/mysql|trilogy/i, error.message)
  end

  def test_plain_update_all_still_works
    assert_equal 2, User.where(role: :admin).update_all(role: :member)
  end
end
