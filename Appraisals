# frozen_string_literal: true

appraise "rails-7.2" do
  gem "rails", "~> 7.2.0"
end

appraise "rails-8.0" do
  gem "rails", "~> 8.0.0"
end

appraise "rails-8.1" do
  gem "rails", "~> 8.1.0"
end

# rails-main is for local testing only and is intentionally not run in CI
appraise "rails-main" do
  gem "rails", github: "rails/rails", branch: "main"
end
