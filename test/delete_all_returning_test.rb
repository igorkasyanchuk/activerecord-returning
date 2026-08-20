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

  def test_can_be_called_on_the_model_itself
    result = Session.delete_all_returning(returning: :id)

    assert_equal 3, result.rows.size
    assert_equal 0, Session.count
  end

  def test_joins_does_not_make_the_primary_key_ambiguous
    result = Session.joins(:user).where(users: { role: :admin }).delete_all_returning(returning: :id)

    assert_equal 2, result.rows.size
    assert_equal 1, Session.count
  end

  def test_eager_loading_raises
    assert_raises(ActiveRecord::Returning::Error) do
      Session.includes(:user).where(users: { role: :admin }).delete_all_returning
    end
  end

  def test_model_without_a_primary_key_raises
    assert_raises(ActiveRecord::Returning::Error) { Legacy.all.delete_all_returning }
  end

  def test_composite_primary_key
    skip "composite primary keys need Rails 7.1+" unless composite_primary_keys?

    result = Note.where(shop_id: 1).delete_all_returning(returning: %i[shop_id note_id])

    assert_equal [[1, 1], [1, 2]], result.rows.sort
    assert_equal 1, Note.count
  end

  def test_the_query_cache_is_cleared
    session = Session.first
    ActiveRecord::Base.connection.enable_query_cache!

    Session.find(session.id)
    Session.where(id: session.id).delete_all_returning

    assert_nil Session.find_by(id: session.id)
  ensure
    ActiveRecord::Base.connection.disable_query_cache!
  end

  def test_group_raises
    assert_raises(ActiveRecord::Returning::Error) { Session.group(:user_id).delete_all_returning }
  end

  def test_having_without_group_raises_too
    assert_raises(ActiveRecord::Returning::Error) { Session.having("COUNT(*) > 0").delete_all_returning }
  end

  def test_unscoping_the_group_makes_it_work_again
    result = Session.group(:user_id).unscope(:group).delete_all_returning(returning: :id)

    assert_equal 3, result.rows.size
    assert_equal 0, Session.count
  end

  def test_the_documented_workaround_for_a_grouped_relation
    grouped = Session.group(:user_id).select("MIN(id) AS id")

    result = Session.where(id: grouped).delete_all_returning(returning: :id)

    assert_equal 3, result.rows.size # one session per user
  end

  def test_empty_returning_list_raises
    assert_raises(ArgumentError) { Session.all.delete_all_returning(returning: []) }
  end

  def test_plain_delete_all_still_returns_an_integer
    assert_equal 3, Session.all.delete_all
  end
end
