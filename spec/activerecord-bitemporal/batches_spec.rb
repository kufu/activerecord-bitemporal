# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "Batches" do
  def create_employees_with_history
    Employee
      .create!([{ name: "Jane" }, { name: "Tom" }, { name: "Bob" }])
      .each { |e| e.update!(updated_at: Time.current) }
  end

  describe "#find_each" do
    context "on BTDM" do
      let(:employees) { create_employees_with_history }

      it "returns all records in batches" do
        expected = [employees[0], employees[1], employees[2]]
        expect(Employee.find_each(batch_size: 1).to_a).to match_array expected
      end
    end

    context "on relation" do
      let(:employees) { create_employees_with_history }

      it "returns all records in batches" do
        expected = [employees[0], employees[1], employees[2]]
        expect(Employee.all.find_each(batch_size: 1).to_a).to match_array expected
      end
    end

    context "on loaded relation" do
      let(:employees) { create_employees_with_history }

      it "returns all records in batches" do
        expected = [employees[0], employees[1], employees[2]]
        expect(Employee.all.load.find_each(batch_size: 1).to_a).to match_array expected
      end
    end

    context "with eager loading by includes" do
      let(:company) {
        Company
          .create!(name: "Company")
          .tap { |c| c.employees << create_employees_with_history }
      }

      it "returns all records in batches" do
        expected = [company.employees[0], company.employees[1], company.employees[2]]
        expect(Employee.includes(:company).find_each(batch_size: 1).to_a).to match_array expected
      end
    end

    context "on association" do
      let(:company) {
        Company
          .create!(name: "Company")
          .tap { |c| c.employees << create_employees_with_history }
      }

      it "returns all records in batches" do
        expected = [company.employees[0], company.employees[1], company.employees[2]]
        expect(company.employees.find_each(batch_size: 1).to_a).to match_array expected
      end
    end
  end

  describe "#find_in_batches" do
    context "on BTDM" do
      let(:employees) { create_employees_with_history }

      it "returns all records in batches" do
        expected = [employees[0], employees[1], employees[2]]
        expect(Employee.find_in_batches(batch_size: 1).to_a.flatten).to match_array expected
      end
    end
  end

  describe "#in_batches" do
    context "on BTDM" do
      let(:employees) { create_employees_with_history }

      it "returns all records in batches" do
        expected = [employees[0], employees[1], employees[2]]
        expect(Employee.in_batches(of: 1).to_a.flatten).to match_array expected
      end
    end
  end
end
