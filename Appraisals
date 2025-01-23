# frozen_string_literal: true

appraise "rails-6.1" do
  gem "rails", "~> 6.1.0"

  # NOTE: concurrent-ruby gem no longer loads the logger gem since v1.3.5.
  #       https://github.com/ruby-concurrency/concurrent-ruby/pull/1062
  #       https://github.com/rails/rails/pull/54264
  gem "concurrent-ruby", "< 1.3.5"
end

appraise "rails-7.0" do
  gem "rails", "~> 7.0.1"

  # for Ruby 3.4
  gem "base64"
  gem "bigdecimal"
  gem "mutex_m"

  # NOTE: concurrent-ruby gem no longer loads the logger gem since v1.3.5.
  #       https://github.com/ruby-concurrency/concurrent-ruby/pull/1062
  #       https://github.com/rails/rails/pull/54264
  gem "concurrent-ruby", "< 1.3.5"
end

appraise "rails-7.1" do
  gem "rails", "~> 7.1.0"
end

appraise "rails-7.2" do
  gem "rails", "~> 7.2.0"
end
