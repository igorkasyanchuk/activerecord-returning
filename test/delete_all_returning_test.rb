# frozen_string_literal: true

require "test_helper"

class DeleteAllReturningTest < ReturningTest
  def test_returns_the_deleted_rows
    result = Session.where(expires_at: ...Time.current).delete_all_returning(returning: %i[id user_id])

    assert_equal %w[id user_id], result.columns
    assert_equal 2, result.rows.size
    assert_equal 1, Session.count
  end

  def test_defaults_to_the_primary_key
    result = Session.where(expires_at: ...Time.current).delete_all_returning

    assert_equal %w[id], result.columns
    assert_equal 2, result.rows.size
  end

  def test_returning_all
    result = Session.where(expires_at: ...Time.current).delete_all_returning(returning: :all)

    assert_equal Session.column_names.sort, result.columns.sort
  end

  def test_none_deletes_nothing
    result = Session.none.delete_all_returning

    assert_empty result.to_a
    assert_equal 3, Session.count
  end

  def test_limit_and_order
    result = Session.order(:id).limit(1).delete_all_returning(returning: :id)

    assert_equal 1, result.rows.size
    assert_equal 2, Session.count
  end

  def test_association_proxy
    user = User.find_by(email: "ada@example.com")

    result = user.sessions.delete_all_returning(returning: :user_id)

    assert_equal [[user.id]], result.rows
    assert_equal 2, Session.count
  end

  def test_bare_string_returning_raises
    assert_raises(ArgumentError) { Session.all.delete_all_returning(returning: "id") }
  end

  def test_plain_delete_all_still_returns_an_integer
    assert_equal 3, Session.all.delete_all
  end
end
