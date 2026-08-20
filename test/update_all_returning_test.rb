# frozen_string_literal: true

require "test_helper"

class UpdateAllReturningTest < ReturningTest
  def test_returns_the_requested_columns_for_updated_rows
    result = User.where(role: :admin).update_all_returning({ role: :member }, returning: %i[id email])

    assert_kind_of ActiveRecord::Result, result
    assert_equal %w[id email], result.columns
    assert_equal ["ada@example.com", "grace@example.com"], result.to_a.map { |row| row["email"] }.sort
  end

  def test_defaults_to_the_primary_key
    result = User.where(role: :admin).update_all_returning(role: :member)

    assert_equal %w[id], result.columns
    assert_equal User.where(email: %w[ada@example.com grace@example.com]).pluck(:id).sort, result.rows.flatten.sort
  end

  def test_rows_outside_the_scope_are_untouched
    User.where(role: :admin).update_all_returning(email: "changed@example.com")

    assert_equal "linus@example.com", User.find_by(role: :member).email
  end

  def test_limit_and_order_are_respected
    result = User.order(:email).limit(1).update_all_returning({ email: "first@example.com" }, returning: :email)

    assert_equal [["first@example.com"]], result.rows
    assert_equal 1, User.where(email: "first@example.com").count
  end

  def test_joins_does_not_make_the_primary_key_ambiguous
    result = User.joins(:posts).where(posts: { published: true })
                 .update_all_returning({ role: :member }, returning: :email)

    assert_equal ["ada@example.com", "grace@example.com"], result.rows.flatten.sort
  end

  def test_none_updates_nothing
    result = User.none.update_all_returning(role: :member)

    assert_empty result.to_a
    assert_equal 2, User.where(role: :admin).count
  end

  def test_returning_all_yields_every_column
    result = User.where(email: "linus@example.com").update_all_returning({ role: :admin }, returning: :all)

    assert_equal User.column_names.sort, result.columns.sort
    assert_equal "linus@example.com", result.to_a.first["email"]
  end

  def test_arel_sql_passes_through_with_an_alias
    result = User.where(email: "ada@example.com")
                 .update_all_returning({ role: :member }, returning: Arel.sql("id, email AS address"))

    assert_equal %w[id address], result.columns
    assert_equal "ada@example.com", result.to_a.first["address"]
  end

  def test_bare_string_returning_raises
    error = assert_raises(ArgumentError) do
      User.all.update_all_returning({ role: :member }, returning: "id, email")
    end

    assert_match(/Arel\.sql/, error.message)
  end

  def test_returning_false_raises_and_says_what_to_use_instead
    error = assert_raises(ArgumentError) { User.all.update_all_returning({ role: :member }, returning: false) }

    assert_match(/update_all/, error.message)
  end

  def test_empty_updates_raises
    assert_raises(ArgumentError) { User.all.update_all_returning({}) }
  end

  def test_plain_update_all_still_returns_an_integer
    assert_equal 2, User.where(role: :admin).update_all(role: :member)
  end

  def test_optimistic_locking_increments_lock_version
    user = User.find_by(email: "ada@example.com")
    before = user.lock_version

    result = User.where(id: user.id).update_all_returning({ email: "new@example.com" }, returning: :lock_version)

    assert_equal [[before + 1]], result.rows
  end

  def test_explicit_lock_version_is_not_incremented_twice
    user = User.find_by(email: "ada@example.com")

    result = User.where(id: user.id).update_all_returning({ lock_version: 42 }, returning: :lock_version)

    assert_equal [[42]], result.rows
  end

  def test_string_and_array_update_forms
    string_result = User.where(email: "linus@example.com").update_all_returning("role = 1", returning: :role)
    assert_equal [[1]], string_result.rows

    array_result = User.where(email: "linus@example.com")
                       .update_all_returning(["email = ?", "linus2@example.com"], returning: :email)
    assert_equal [["linus2@example.com"]], array_result.rows
  end

  def test_association_proxy
    user = User.find_by(email: "ada@example.com")

    result = user.posts.update_all_returning({ title: "edited" }, returning: :title)

    assert_equal %w[edited edited], result.rows.flatten
    assert_equal ["On compilers"], Post.where.not(user_id: user.id).pluck(:title)
  end

  def test_eager_loading_raises
    error = assert_raises(ActiveRecord::Returning::Error) do
      User.includes(:posts).where(posts: { published: true }).update_all_returning(role: :member)
    end

    assert_match(/joins/, error.message)
  end

  def test_enum_and_boolean_values_are_cast_like_update_all
    User.where(email: "linus@example.com").update_all_returning(role: :admin)
    Post.where(title: "Draft").update_all_returning(published: true)

    assert_predicate User.find_by(email: "linus@example.com"), :admin?
    assert_predicate Post.find_by(title: "Draft"), :published?
  end

  def test_timestamps_are_not_touched
    user = User.find_by(email: "ada@example.com")

    User.where(id: user.id).update_all_returning(email: "other@example.com")

    assert_equal user.updated_at.to_i, user.reload.updated_at.to_i
  end

  def test_composite_primary_key
    skip "composite primary keys need Rails 7.1+" unless composite_primary_keys?

    result = Note.where(shop_id: 1).update_all_returning({ body: "edited" }, returning: %i[shop_id note_id body])

    assert_equal [[1, 1, "edited"], [1, 2, "edited"]], result.rows.sort
    assert_equal "other shop", Note.find_by(shop_id: 2).body
  end

  def test_model_without_a_primary_key_raises
    error = assert_raises(ActiveRecord::Returning::Error) { Legacy.all.update_all_returning(name: "x") }

    assert_match(/primary key/, error.message)
  end

  def test_can_be_called_on_the_model_itself
    result = User.update_all_returning({ role: :member }, returning: :id)

    assert_equal User.pluck(:id).sort, result.rows.flatten.sort
    assert_equal 0, User.where(role: :admin).count
  end

  def test_alias_attribute_names_are_resolved
    result = Post.where(title: "Draft").update_all_returning({ headline: "Edited" }, returning: :title)

    assert_equal [["Edited"]], result.rows
  end

  def test_alias_attribute_names_are_resolved_in_returning
    result = Post.where(title: "Draft").update_all_returning({ title: "Edited" }, returning: %i[id headline])

    assert_equal %w[id headline], result.columns
    assert_equal "Edited", result.to_a.first["headline"]
  end

  def test_json_columns_are_serialized_like_update_all
    Post.where(title: "Draft").update_all_returning(metadata: { "source" => "import" })

    assert_equal({ "source" => "import" }, Post.find_by(title: "Draft").metadata)
  end

  def test_the_query_cache_is_cleared
    user = User.first
    ActiveRecord::Base.connection.enable_query_cache!

    User.find(user.id) # caches the row
    User.where(id: user.id).update_all_returning(email: "fresh@example.com")

    assert_equal "fresh@example.com", User.find(user.id).email
  ensure
    ActiveRecord::Base.connection.disable_query_cache!
  end

  def test_values_can_be_cast_with_the_models_types
    result = User.where(email: "ada@example.com").update_all_returning({ role: :member }, returning: :all)

    row = result.cast_values(User.attribute_types).first

    assert_kind_of Time, row[User.column_names.index("created_at")]
  end

  def test_lock_is_allowed_inside_the_subquery
    result = User.where(role: :admin).lock.update_all_returning({ role: :member }, returning: :id)

    assert_equal 2, result.rows.size
  end

  def test_distinct
    result = User.distinct.update_all_returning({ role: :member }, returning: :id)

    assert_equal User.count, result.rows.size
  end

  def test_single_table_inheritance_only_touches_the_subclass
    result = Memo.update_all_returning({ title: "edited" }, returning: %i[type title])

    assert_equal [["Memo", "edited"]], result.rows
    assert_equal "plain document", Document.find_by(type: nil).title
  end

  def test_group_raises_rather_than_building_an_invalid_subquery
    error = assert_raises(ActiveRecord::Returning::Error) do
      User.group(:role).update_all_returning(role: :member)
    end

    assert_match(/group/, error.message)
  end

  def test_having_without_group_raises_too
    error = assert_raises(ActiveRecord::Returning::Error) do
      User.having("COUNT(*) > 0").update_all_returning(role: :member)
    end

    assert_match(/having/, error.message)
  end

  def test_group_and_having_together_raise
    assert_raises(ActiveRecord::Returning::Error) do
      User.group(:role).having("COUNT(*) > 1").update_all_returning(role: :member)
    end
  end

  def test_unscoping_the_group_makes_it_work_again
    result = User.group(:role).unscope(:group).update_all_returning({ role: :member }, returning: :id)

    assert_equal User.count, result.rows.size
  end

  def test_the_documented_workaround_for_a_grouped_relation
    # What the error message tells you to do.
    grouped = User.group(:role).select("MIN(id) AS id")

    result = User.where(id: grouped).update_all_returning({ role: :member }, returning: :id)

    assert_equal 2, result.rows.size # one per role
  end

  def test_empty_returning_list_raises
    assert_raises(ArgumentError) { User.all.update_all_returning({ role: :member }, returning: []) }
  end

  def test_postgresql_array_columns
    skip "PostgreSQL only" unless Dev::ADAPTER == "postgres"

    ActiveRecord::Base.connection.add_column(:posts, :tags, :string, array: true) unless Post.column_names.include?("tags")
    Post.reset_column_information

    result = Post.where(title: "Draft").update_all_returning({ tags: %w[a b] }, returning: :tags)

    assert_equal 1, result.rows.size
    assert_equal %w[a b], Post.find_by(title: "Draft").tags
  end

  def test_relation_is_reset_after_updating
    relation = User.where(role: :admin)
    relation.load

    relation.update_all_returning(email: "reset@example.com")

    refute_predicate relation, :loaded?
  end
end
