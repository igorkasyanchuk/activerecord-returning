# frozen_string_literal: true

# Tiny dummy app: an in-memory SQLite database with a few models.
# Used by the test suite and by bin/console.

require "active_record"
require "activerecord-returning"

# DATABASE_URL lets the same app (and the test suite) run against PostgreSQL.
ActiveRecord::Base.establish_connection(ENV["DATABASE_URL"] || { adapter: "sqlite3", database: ":memory:" })
ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  create_table :users, force: true do |t|
    t.string :email
    t.integer :role, default: 0
    t.integer :lock_version, default: 0
    t.timestamps
  end

  create_table :posts, force: true do |t|
    t.integer :user_id
    t.string :title
    t.boolean :published, default: false
    t.timestamps
  end

  create_table :sessions, force: true do |t|
    t.integer :user_id
    t.datetime :expires_at
  end

  create_table :legacy_rows, force: true, id: false do |t|
    t.string :name
  end

  create_table :notes, force: true, id: false do |t|
    t.integer :shop_id, null: false
    t.integer :note_id, null: false
    t.string :body
  end
end

class User < ActiveRecord::Base
  enum :role, { member: 0, admin: 1 }
  has_many :posts
  has_many :sessions
end

class Post < ActiveRecord::Base
  belongs_to :user
end

class Session < ActiveRecord::Base
  belongs_to :user
end

# A table with no primary key at all.
class Legacy < ActiveRecord::Base
  self.table_name = "legacy_rows"
end

# Composite primary keys landed in Rails 7.1.
if ActiveRecord::VERSION::STRING >= "7.1"
  class Note < ActiveRecord::Base
    self.primary_key = [:shop_id, :note_id]
  end
end

module DemoApp
  module_function

  def seed!
    [User, Post, Session, Legacy].each(&:delete_all)
    Note.delete_all if defined?(Note)

    ada = User.create!(email: "ada@example.com", role: :admin)
    grace = User.create!(email: "grace@example.com", role: :admin)
    linus = User.create!(email: "linus@example.com", role: :member)

    ada.posts.create!(title: "Notes on the Analytical Engine", published: true)
    ada.posts.create!(title: "Draft", published: false)
    grace.posts.create!(title: "On compilers", published: true)

    Session.create!(user: ada, expires_at: 2.weeks.ago)
    Session.create!(user: grace, expires_at: 1.day.from_now)
    Session.create!(user: linus, expires_at: 3.weeks.ago)

    Legacy.create!(name: "no primary key here")

    if defined?(Note)
      Note.create!(shop_id: 1, note_id: 1, body: "first")
      Note.create!(shop_id: 1, note_id: 2, body: "second")
      Note.create!(shop_id: 2, note_id: 1, body: "other shop")
    end

    :ok
  end
end
