# frozen_string_literal: true

class User < ActiveRecord::Base
  enum :role, { member: 0, admin: 1 }
  has_many :posts
  has_many :sessions
end

class Post < ActiveRecord::Base
  belongs_to :user
  alias_attribute :headline, :title
end

class Session < ActiveRecord::Base
  belongs_to :user
end

class Document < ActiveRecord::Base; end
class Memo < Document; end

class Legacy < ActiveRecord::Base
  self.table_name = "legacy_rows"
end

# Composite primary keys landed in Rails 7.1.
if ActiveRecord::VERSION::STRING >= "7.1"
  class Note < ActiveRecord::Base
    self.primary_key = [:shop_id, :note_id]
  end
end
