# frozen_string_literal: true

require "test_helper"

# The per-method test files cover each relation feature once. This one runs the
# same relation shapes — and their combinations — through *both* methods, so a
# shape that works for UPDATE cannot quietly break for DELETE.
#
# Every case asserts the same three things: the rows the relation selects are
# the rows returned, the rows returned are the rows the database changed, and
# nothing outside the relation moved. The expectation is plucked from the
# relation itself before the statement runs, so a case can never assert against
# the same wrong set the subquery built.
class CombinationsTest < ReturningTest
  SENTINEL = Time.utc(2030, 1, 1)

  # Sessions, because both methods can be pointed at the same three rows:
  # ada's and linus's are expired, grace's is not.
  SCOPES = {
    "all" => -> { Session.all },
    "where" => -> { Session.where(expires_at: ...Time.current) },
    "where + not" => -> { Session.where(expires_at: ...Time.current).where.not(user_id: nil) },
    "where + or" => -> { Session.where(expires_at: ...Time.current).or(Session.where(user_id: nil)) },
    "where + rewhere" => -> { Session.where(expires_at: Time.current...).rewhere(expires_at: ...Time.current) },
    "where + merge" => -> { Session.where(expires_at: ...Time.current).merge(Session.where.not(user_id: nil)) },
    "where + unscope" => -> { Session.where(user_id: -1).unscope(:where) },
    "order + limit" => -> { Session.order(:id).limit(2) },
    "order + limit + offset" => -> { Session.order(:id).limit(2).offset(1) },
    "order desc + limit" => -> { Session.order(id: :desc).limit(1) },
    "where + order + limit" => -> { Session.where(expires_at: ...Time.current).order(:expires_at).limit(1) },
    "joins" => -> { Session.joins(:user).where(users: { role: :admin }) },
    "joins + order + limit" => -> { Session.joins(:user).where(users: { role: :admin }).order(:id).limit(1) },
    "left_joins + distinct" => -> { Session.left_joins(:user).distinct },
    "distinct + order + limit" => -> { Session.distinct.order(:id).limit(2) },
    "where with a subquery" => -> { Session.where(user_id: User.where(role: :admin).select(:id)) },
    # The only orphan the suite has; without it this shape matches nothing and
    # the case would assert against two empty sets.
    "where.missing" => lambda {
      Session.create!(user_id: nil, expires_at: 2.days.ago)
      Session.where.missing(:user)
    },
    "select is ignored" => -> { Session.select(:user_id).where(expires_at: ...Time.current) },
    "readonly" => -> { Session.readonly.where(expires_at: ...Time.current) },
    "lock" => -> { Session.where(expires_at: ...Time.current).lock },
    "association proxy" => -> { User.find_by(email: "ada@example.com").sessions },
    "association proxy + where + order + limit" => lambda {
      User.find_by(email: "ada@example.com").sessions.where.not(user_id: nil).order(:id).limit(1)
    },
    "default scope" => -> { ExpiredSession.all },
    "default scope + order + limit" => -> { ExpiredSession.order(:id).limit(1) },
    "default scope + unscoped where" => -> { ExpiredSession.where(user_id: -1).unscope(:where) },
    "none" => -> { Session.none }
  }.freeze

  SCOPES.each do |name, scope|
    method_name = name.gsub(/[^a-z0-9]+/i, "_")

    # One relation object per test, built once: a scope that has to set up a row
    # to match would otherwise set it up twice, and the counts would not add up.
    define_method("test_update_#{method_name}") do
      relation = scope.call
      expected = ids_for(relation)
      refute_empty expected, "#{name} matches no rows, so this case would assert nothing" unless name == "none"

      result = relation.update_all_returning(expires_at: SENTINEL)

      assert_equal %w[id], result.columns
      assert_equal expected, result.rows.flatten.sort
      assert_equal expected, Session.where(expires_at: SENTINEL).pluck(:id).sort
    end

    define_method("test_delete_#{method_name}") do
      relation = scope.call
      expected = ids_for(relation)
      refute_empty expected, "#{name} matches no rows, so this case would assert nothing" unless name == "none"
      before = Session.count

      result = relation.delete_all_returning

      assert_equal %w[id], result.columns
      assert_equal expected, result.rows.flatten.sort
      assert_empty Session.where(id: expected)
      assert_equal before - expected.size, Session.count
    end
  end

  # returning: is orthogonal to the relation, so one plain scope is enough to
  # cover every form of it against both methods.
  RETURNING_FORMS = {
    "default" => [nil, %w[id]],
    "symbol" => [:user_id, %w[user_id]],
    "array" => [%i[id user_id], %w[id user_id]],
    "all" => [:_all, %w[id user_id expires_at]],
    "arel sql" => [Arel.sql("id AS session_id"), %w[session_id]]
  }.freeze

  RETURNING_FORMS.each do |name, (returning, columns)|
    method_name = name.gsub(/[^a-z0-9]+/i, "_")

    define_method("test_update_returning_#{method_name}") do
      result = expired.update_all_returning({ expires_at: SENTINEL }, returning: returning)

      assert_equal columns.sort, result.columns.sort
      assert_equal 2, result.rows.size
    end

    define_method("test_delete_returning_#{method_name}") do
      result = expired.delete_all_returning(returning: returning)

      assert_equal columns.sort, result.columns.sort
      assert_equal 2, result.rows.size
    end
  end

  # Relations both methods refuse, with the reason each message has to name.
  REJECTED = {
    "eager loading" => [-> { Session.includes(:user).where(users: { role: :admin }) }, /joins/],
    "group" => [-> { Session.group(:user_id) }, /group/],
    "having" => [-> { Session.having("COUNT(*) > 0") }, /having/],
    "group + having" => [-> { Session.group(:user_id).having("COUNT(*) > 0") }, /group/],
    "from" => [-> { Session.from("sessions AS s").where("s.user_id IS NOT NULL") }, /from/],
    "from + joins" => [-> { Session.from("sessions AS s").joins("JOIN users ON users.id = s.user_id") }, /from/]
  }.freeze

  REJECTED.each do |name, (scope, message)|
    method_name = name.gsub(/[^a-z0-9]+/i, "_")

    define_method("test_update_rejects_#{method_name}") do
      error = assert_raises(ActiveRecord::Returning::Error) { scope.call.update_all_returning(expires_at: SENTINEL) }

      assert_match message, error.message
      assert_equal 3, Session.count
      assert_equal 0, Session.where(expires_at: SENTINEL).count, "nothing should have been updated"
    end

    define_method("test_delete_rejects_#{method_name}") do
      error = assert_raises(ActiveRecord::Returning::Error) { scope.call.delete_all_returning }

      assert_match message, error.message
      assert_equal 3, Session.count, "nothing should have been deleted"
    end
  end

  # `from` is the one that used to pass. The subquery selects sessions.id while
  # FROM names the table something else, so the database reads sessions.id as a
  # reference to the row being changed and every row matches — a whole-table
  # UPDATE from a relation that selects one row. Rejected now; this pins it.
  def test_from_does_not_touch_rows_outside_the_relation
    scope = Session.from("sessions AS s").where("s.expires_at < ?", Time.current)

    assert_equal 2, scope.count, "the relation itself selects two of the three rows"
    assert_raises(ActiveRecord::Returning::Error) { scope.update_all_returning(expires_at: SENTINEL) }
    assert_equal 0, Session.where(expires_at: SENTINEL).count
  end

  def test_unscoping_from_makes_it_work_again
    result = Session.from("sessions AS s").unscope(:from)
                    .where(expires_at: ...Time.current).update_all_returning(expires_at: SENTINEL)

    assert_equal 2, result.rows.size
    assert_equal 2, Session.where(expires_at: SENTINEL).count
  end

  # `delete_all` on a has_many proxy nullifies the foreign key unless the
  # association says dependent: :delete_all. delete_all_returning always
  # deletes, because a RETURNING of rows that still exist would be a lie. The
  # README says so; this is the proof it stays that way.
  def test_delete_all_returning_on_an_association_deletes_rather_than_nullifying
    user = User.find_by(email: "ada@example.com")

    result = user.posts.delete_all_returning(returning: :id)

    assert_equal 2, result.rows.size
    assert_equal 1, Post.count
    assert_equal 0, Post.where(user_id: nil).count, "delete_all would have nullified these instead"
  end

  private
    def expired = Session.where(expires_at: ...Time.current)

    # What the relation selects, asked before the statement runs.
    def ids_for(relation) = relation.unscope(:select).pluck(:id).sort
end
