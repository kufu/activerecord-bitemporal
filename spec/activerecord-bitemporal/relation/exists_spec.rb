# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecord::Bitemporal::Relation do
  describe "#exists?" do
    def create_employees_with_history
      Employee
        .create!([{ name: "Jane" }, { name: "Tom" } ])
        .each { |e| e.update!(updated_at: Time.current) }
    end

    # Assuming that the number of records will not reach the maximum value in tests.
    # employees.bitemporal_id is a 4-byte signed integer.
    MAX_BITEMPORAL_ID = 1 << 31 - 1

    context "on BTDM" do
      let(:employees) { create_employees_with_history }

      it "finds existing bitemporal IDs" do
        first_employee, second_employee = *employees

        expect(Employee.exists?(first_employee.bitemporal_id)).to eq true
        expect(Employee.exists?(second_employee.bitemporal_id)).to eq true
        expect(Employee.exists?(MAX_BITEMPORAL_ID)).to eq false
      end
    end

    context "on relation" do
      let(:employees) { create_employees_with_history }

      it "finds existing bitemporal IDs" do
        first_employee, second_employee = *employees

        expect(Employee.all.exists?(first_employee.bitemporal_id)).to eq true
        expect(Employee.all.exists?(second_employee.bitemporal_id)).to eq true
        expect(Employee.all.exists?(MAX_BITEMPORAL_ID)).to eq false
      end
    end

    context "on loaded relation" do
      let(:employees) { create_employees_with_history }

      it "finds existing bitemporal IDs" do
        first_employee, second_employee = *employees

        expect(Employee.all.load.exists?(first_employee.bitemporal_id)).to eq true
        expect(Employee.all.load.exists?(second_employee.bitemporal_id)).to eq true
        expect(Employee.all.load.exists?(MAX_BITEMPORAL_ID)).to eq false
      end
    end

    context "with eager loading by includes" do
      let(:company) {
        Company
          .create!(name: "Company")
          .tap { |c| c.employees << create_employees_with_history }
      }

      it "finds existing bitemporal IDs" do
        first_employee, second_employee = *company.employees

        expect(Employee.includes(:company).exists?(first_employee.bitemporal_id)).to eq true
        expect(Employee.includes(:company).exists?(second_employee.bitemporal_id)).to eq true
        expect(Employee.includes(:company).exists?(MAX_BITEMPORAL_ID)).to eq false
      end
    end

    context "on association" do
      let(:company) {
        Company
          .create!(name: "Company")
          .tap { |c| c.employees << create_employees_with_history }
      }

      it "finds existing bitemporal IDs" do
        first_employee, second_employee = *company.employees

        expect(company.employees.reset.exists?(first_employee.bitemporal_id)).to eq true
        expect(company.employees.reset.exists?(second_employee.bitemporal_id)).to eq true
        expect(company.employees.reset.exists?(MAX_BITEMPORAL_ID)).to eq false
      end
    end
  end
end
