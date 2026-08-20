# frozen_string_literal: true

ActiveRecord::Schema.verbose = false

ActiveRecord::Schema.define do
  create_table :users, force: true do |t|
    t.string :email
    t.integer :role, default: 0
    t.integer :lock_version, default: 0   # optimistic locking
    t.timestamps
  end

  create_table :posts, force: true do |t|
    t.integer :user_id
    t.string :title
    t.boolean :published, default: false
    t.json :metadata
    t.timestamps
  end

  create_table :sessions, force: true do |t|
    t.integer :user_id
    t.datetime :expires_at
  end

  # Single table inheritance.
  create_table :documents, force: true do |t|
    t.string :type
    t.string :title
  end

  # No primary key at all.
  create_table :legacy_rows, force: true, id: false do |t|
    t.string :name
  end

  # Composite primary key. The model only declares it on Rails 7.1+, so the
  # table is created without one and the columns are spelled out.
  create_table :notes, force: true, id: false do |t|
    t.integer :shop_id, null: false
    t.integer :note_id, null: false
    t.string :body
  end
end
