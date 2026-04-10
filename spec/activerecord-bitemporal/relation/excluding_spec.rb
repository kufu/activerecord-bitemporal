# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "#excluding (#without)" do
  def create_employees_with_history
    Employee
      .create!([{ name: "Jane" }, { name: "Tom" }, { name: "Bob" }])
      .each { |e| e.update!(updated_at: Time.current) }
  end

  describe "#excluding" do
    context "with record objects" do
      let!(:employees) { create_employees_with_history }

      it "excludes the specified record by bitemporal_id" do
        excluded = employees[0]
        result = Employee.excluding(excluded)
        expect(result).to match_array [employees[1], employees[2]]
        expect(result).not_to include(excluded)
      end

      it "excludes multiple records by bitemporal_id" do
        result = Employee.excluding(employees[0], employees[1])
        expect(result).to match_array [employees[2]]
      end
    end

    context "with a Relation" do
      let!(:employees) { create_employees_with_history }

      it "excludes records from the relation" do
        excluded_relation = Employee.where(name: "Jane")
        result = Employee.excluding(excluded_relation)
        expect(result).to match_array [employees[1], employees[2]]
      end
    end

    context "on association" do
      let!(:company) {
        Company
          .create!(name: "Company")
          .tap { |c| c.employees << create_employees_with_history }
      }

      it "excludes the specified record" do
        employees = company.employees.to_a
        result = company.employees.excluding(employees[0])
        expect(result).to match_array [employees[1], employees[2]]
      end
    end
  end

  describe "#without" do
    let!(:employees) { create_employees_with_history }

    it "is an alias for excluding" do
      excluded = employees[0]
      result = Employee.without(excluded)
      expect(result).to match_array [employees[1], employees[2]]
    end
  end
end
