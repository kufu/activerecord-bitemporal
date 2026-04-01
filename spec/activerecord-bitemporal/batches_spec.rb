# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "Batches" do
  def create_employees_with_history
    Employee
      .create!([{ name: "Jane" }, { name: "Tom" }, { name: "Bob" } ])
      .each { |e| e.update!(updated_at: Time.current) }
  end

  describe "#find_each" do
    context "on BTDM" do
      let(:employees) { create_employees_with_history }

      it "returns all records" do
        expected = [employees[0], employees[1], employees[2]]
        expect(Employee.find_each(batch_size: 1).to_a).to match_array expected
      end
    end
  end
end
