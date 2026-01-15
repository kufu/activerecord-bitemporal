# frozen_string_literal: true

require "spec_helper"

RSpec.describe "implicit_order_column for Rails 8+" do
  describe "configuration" do
    context "when Rails 8.0 or later", if: ActiveRecord.gem_version >= Gem::Version.new("8.0.0") do
      it "sets implicit_order_column to [bitemporal_id, nil]" do
        expect(Employee.implicit_order_column).to eq(["bitemporal_id", nil])
      end

      it "prevents automatic primary_key appending with nil-terminated array" do
        expect(Employee.implicit_order_column.last).to be_nil
      end
    end

    context "when Rails 7.x", if: ActiveRecord.gem_version < Gem::Version.new("8.0.0") do
      it "does not set implicit_order_column" do
        expect(Employee.implicit_order_column).to be_nil
      end
    end
  end

  describe "user-defined implicit_order_column", if: ActiveRecord.gem_version >= Gem::Version.new("8.0.0") do
    it "respects user-defined value (not overwritten)" do
      # Create a temporary model with user-defined implicit_order_column
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "employees"
        self.implicit_order_column = ["name", nil]
        include ActiveRecord::Bitemporal
        bitemporalize
      end

      # User-defined value should be preserved
      expect(klass.implicit_order_column).to eq(["name", nil])
    end
  end

  describe ".first ordering", if: ActiveRecord.gem_version >= Gem::Version.new("8.0.0") do
    before do
      3.times { |i| Employee.create!(name: "Employee#{i + 1}") }
    end

    it "returns record with smallest bitemporal_id" do
      expect(Employee.first.bitemporal_id).to eq(Employee.minimum(:bitemporal_id))
    end
  end

  describe ".last ordering", if: ActiveRecord.gem_version >= Gem::Version.new("8.0.0") do
    before do
      3.times { |i| Employee.create!(name: "Employee#{i + 1}") }
    end

    it "returns record with largest bitemporal_id" do
      expect(Employee.last.bitemporal_id).to eq(Employee.maximum(:bitemporal_id))
    end
  end

  describe "edge cases", if: ActiveRecord.gem_version >= Gem::Version.new("8.0.0") do
    it "respects user-defined single string value" do
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "employees"
        self.implicit_order_column = "created_at"
        include ActiveRecord::Bitemporal
        bitemporalize
      end

      expect(klass.implicit_order_column).to eq("created_at")
    end

    it "uses custom bitemporal_id_key in implicit_order_column" do
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "employees"

        def self.bitemporal_id_key
          "original_id"
        end

        include ActiveRecord::Bitemporal
        bitemporalize
      end

      expect(klass.implicit_order_column).to eq(["original_id", nil])
    end

    it ".second uses implicit_order_column ordering" do
      3.times { |i| Employee.create!(name: "Employee#{i + 1}") }
      first_id = Employee.first.bitemporal_id
      second_id = Employee.second.bitemporal_id

      expect(second_id).to be > first_id
    end
  end
end
