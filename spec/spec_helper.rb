# frozen_string_literal: true

require "active_record"
require "activerecord-bitemporal"

require "bundler"
Bundler.require(:default, :development)

dbconfig = YAML::load(IO.read(File.join(File.dirname(__FILE__), "database.yml")))["test"]
ActiveRecord::Base.establish_connection(dbconfig.merge(database: 'postgres'))

RSpec.configure do |config|
  config.order = :random

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

  config.around(:each) do |example|
    conn = ActiveRecord::Base.connection
    if example.metadata[:use_truncation]
      example.run
      conn.truncate_tables(*conn.tables)
    else
      conn.transaction do
        example.run
        raise ActiveRecord::Rollback
      end
    end
  end
end

require 'schema'
