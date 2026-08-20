# frozen_string_literal: true

require_relative "lib/activerecord/returning/version"

Gem::Specification.new do |spec|
  spec.name = "activerecord-returning"
  spec.version = ActiveRecord::Returning::VERSION
  spec.authors = ["Igor Kasyanchuk"]
  spec.email = ["igorkasyanchuk@gmail.com"]

  spec.summary = "UPDATE ... RETURNING and DELETE ... RETURNING for ActiveRecord::Relation"
  spec.description = "Adds update_all_returning and delete_all_returning to ActiveRecord::Relation, " \
                     "so you get the changed rows back instead of a row count. PostgreSQL and SQLite 3.35+."
  spec.homepage = "https://github.com/igorkasyanchuk/activerecord-returning"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["documentation_uri"] = "#{spec.homepage}/blob/main/README.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.0", "< 9.0"
end
