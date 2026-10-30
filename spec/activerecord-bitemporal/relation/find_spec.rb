# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecord::Bitemporal::Relation do
  describe "#find" do
    def create_employees_with_history
      Employee
        .create!([{ name: "Jane" }, { name: "Tom" } ])
        .each { |e| e.update!(updated_at: Time.current) }
    end

    let!(:employees) { create_employees_with_history }

    context "on BTDM" do
      it "finds a record by bitemporal ID" do
        first_employee = employees.first

        expect(Employee.find(first_employee.bitemporal_id)).to eq first_employee
      end

      it "finds records in the order of the given bitemporal IDs" do
        first_employee, second_employee = *employees

        expect(
          Employee.find([
            second_employee.bitemporal_id.to_s,
            first_employee.bitemporal_id.to_s
          ])
        ).to eq [second_employee, first_employee]
      end

      it "does not find a record by ID of a current record" do
        # currently valid IDs that is not used as any bitemporal_id
        ids = Employee.pluck(:id) - Employee.ignore_valid_datetime.pluck(:bitemporal_id)

        expect { Employee.find(ids.sample) }.to raise_error ActiveRecord::RecordNotFound
      end
    end

    context "on relation" do
      it "finds a record by bitemporal ID" do
        first_employee, second_employee = *employees

        expect(Employee.all.find(first_employee.bitemporal_id)).to eq first_employee
        expect(Employee.all.find(second_employee.bitemporal_id)).to eq second_employee
      end
    end

    context "on association" do
      let!(:company) {
        Company
          .create!(name: "Company")
          .tap { |c| c.employees << employees }
      }

      it "finds a record by bitemporal ID" do
        first_employee, second_employee = *employees

        expect(company.employees.find(first_employee.bitemporal_id)).to eq first_employee
        expect(company.employees.find(second_employee.bitemporal_id)).to eq second_employee
      end
    end
  end
end
