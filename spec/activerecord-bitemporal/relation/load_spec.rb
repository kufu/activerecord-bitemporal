# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecord::Bitemporal::Relation do
  describe "#load" do
    let!(:employees) { Employee.create!([{ name: "Jane" }, { name: "Tom" }]) }

    context "on relation" do
      it "returns self" do
        relation = Employee.all
        expect(relation.load).to equal relation
      end
    end

    context "on loaded relation" do
      it "returns self" do
        relation = Employee.all.load
        expect(relation.load).to equal relation
      end
    end

    context "with valid_at" do
      it "returns self" do
        relation = Employee.valid_at(Time.current)
        expect(relation.load).to equal relation
      end
    end

    context "with transaction_at" do
      it "returns self" do
        relation = Employee.transaction_at(Time.current)
        expect(relation.load).to equal relation
      end
    end

    context "on empty relation" do
      it "returns self" do
        relation = Employee.where(name: "Not Found").valid_at(Time.current)
        expect(relation.load).to equal relation
      end
    end
  end
end
