require "active_record"
require "activerecord-bitemporal"

require "bundler"
Bundler.require(:default, :development)

dbconfig = YAML::load(IO.read(File.join(File.dirname(__FILE__), "database.yml")))["test"]
ActiveRecord::Base.establish_connection(dbconfig.merge(database: 'postgres'))

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  # Create database for test
  connection = ActiveRecord::Base.connection
  connection.drop_database(dbconfig["database"])
  connection.create_database(dbconfig["database"])
  ActiveRecord::Base.establish_connection(dbconfig)

  Time.zone = "UTC"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
  end
  config.before(:each, use_truncation: true) do
    DatabaseCleaner.strategy = :truncation
  end

  config.before(:each) do
    DatabaseCleaner.start
  end

  config.append_after(:each) do
    DatabaseCleaner.clean
  end
end

require 'schema'
