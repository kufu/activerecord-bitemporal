# frozen_string_literal: true

require "spec_helper"

RSpec.describe "implicit_order_column for Rails 8+" do
  describe "configuration" do
    context "when Rails 8.0 or later", if: ActiveRecord.gem_version >= Gem::Version.new("8.0.0") do
      it "sets implicit_order_column to [bitemporal_id, nil]" do
        expect(Employee.implicit_order_column).to eq(["bitemporal_id", nil])
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

    it ".first returns nil for empty table" do
      Employee.delete_all
      expect(Employee.first).to be_nil
    end

    it ".last returns nil for empty table" do
      Employee.delete_all
      expect(Employee.last).to be_nil
    end
  end

  describe "STI inheritance", if: ActiveRecord.gem_version >= Gem::Version.new("8.0.0") do
    # Create STI child class that inherits from Employee
    let(:sti_child_class) do
      Class.new(Employee) do
        def self.name
          "Manager"
        end
      end
    end

    it "inherits implicit_order_column to child classes" do
      expect(sti_child_class.implicit_order_column).to eq(["bitemporal_id", nil])
    end

    it "child class .first uses bitemporal_id ordering" do
      3.times { |i| Employee.create!(name: "Employee#{i + 1}") }

      # Child class should also use bitemporal_id ordering
      expect(sti_child_class.first.bitemporal_id).to eq(Employee.minimum(:bitemporal_id))
    end

    it "child class .last uses bitemporal_id ordering" do
      3.times { |i| Employee.create!(name: "Employee#{i + 1}") }

      expect(sti_child_class.last.bitemporal_id).to eq(Employee.maximum(:bitemporal_id))
    end
  end
end
