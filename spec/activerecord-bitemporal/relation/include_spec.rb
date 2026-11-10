# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecord::Bitemporal::Relation do
  describe "#include?" do
    def create_employees_with_history
      Employee
        .create!([{ name: "Jane" }, { name: "Tom" } ])
        .each { |e| e.update!(updated_at: Time.current) }
    end

    let!(:employees) { create_employees_with_history }

    context "on relation" do
      it "returns whether the relation includes the record" do
        first_employee, second_employee = *employees
        relation = Employee.where(name: "Jane")

        expect(relation.include?(first_employee)).to be true
        expect(relation.include?(second_employee)).to be false
      end
    end

    context "on loaded relation" do
      it "returns whether the relation includes the record" do
        first_employee, second_employee = *employees
        relation = Employee.where(name: "Jane").load

        expect(relation.include?(first_employee)).to be true
        expect(relation.include?(second_employee)).to be false
      end
    end

    context "on association" do
      let!(:company) {
        Company
          .create!(name: "Company")
          .tap { |c| c.employees << employees.first }
      }

      it "returns whether the association includes the record" do
        first_employee, second_employee = *employees

        expect(company.employees.include?(first_employee)).to be true
        expect(company.employees.include?(second_employee)).to be false
      end
    end

    context "on loaded association" do
      let!(:company) {
        Company
          .create!(name: "Company")
          .tap { |c| c.employees << employees.first }
      }

      it "returns whether the association includes the record" do
        first_employee, second_employee = *employees
        company.employees.load

        expect(company.employees.include?(first_employee)).to be true
        expect(company.employees.include?(second_employee)).to be false
      end
    end
  end
end
