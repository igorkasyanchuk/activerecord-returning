# frozen_string_literal: true

module Seeds
  module_function

  # Wipes every table and writes the same small, predictable set of rows the
  # test suite expects.
  def run
    [Post, Session, User, Legacy].each(&:delete_all)
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
