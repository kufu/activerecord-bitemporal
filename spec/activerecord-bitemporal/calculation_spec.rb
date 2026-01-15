# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "Calculation" do
  describe "#ids" do
    def create_employees_with_history
      Employee
        .create!([{ name: "Jane" }, { name: "Tom" } ])
        .each { |e| e.update!(updated_at: Time.current) }
    end

    context "on BTDM" do
      let(:employees) { create_employees_with_history }

      it "returns all bitemporal IDs" do
        expected = [employees[0].bitemporal_id, employees[1].bitemporal_id]
        expect(Employee.ids).to match_array expected
      end
    end

    context "on relation" do
      let(:employees) { create_employees_with_history }

      it "returns all bitemporal IDs" do
        expected = [employees[0].bitemporal_id, employees[1].bitemporal_id]
        expect(Employee.all.ids).to match_array expected
      end
    end

    context "on loaded relation" do
      let(:employees) { create_employees_with_history }

      it "returns all bitemporal IDs" do
        expected = [employees[0].bitemporal_id, employees[1].bitemporal_id]
        expect(Employee.all.load.ids).to match_array expected
      end
    end

    context "with eager loading by includes" do
      let(:company) {
        Company
          .create!(name: "Company")
          .tap { |c| c.employees << create_employees_with_history }
      }

      it "returns bitemporal IDs" do
        expected = [company.employees[0].bitemporal_id, company.employees[1].bitemporal_id]
        expect(Employee.includes(:company).ids).to match_array expected
      end
    end
  end
end
