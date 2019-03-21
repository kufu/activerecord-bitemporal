require 'spec_helper'

class EmployeeWithScope < Employee
  include ActiveRecord::Bitemporal::Scope::Experimental
end

RSpec.describe ActiveRecord::Bitemporal::Scope::Experimental do
  shared_examples "defined records" do
    before do
      emp1 = nil
      emp2 = nil
      Timecop.freeze("2019/1/10") {
        emp1 = EmployeeWithScope.create(name: "Jane")
        emp2 = EmployeeWithScope.create(name: "Homu")
      }

      Timecop.freeze("2019/1/17") {
        emp1.update!(name: "Tom")
        emp2.update!(name: "Mami")
      }

      Timecop.freeze("2019/1/25") {
        emp1.update!(name: "Kevin")
        emp2.update!(name: "Mado")
      }
    end
  end

  describe ".valid_in" do
    include_context "defined records"
    subject { EmployeeWithScope.valid_in(from: from, to: to).pluck(:name).flatten }

    context "2019/1/5 - 2019/1/8" do
      let(:from) { "2019/1/5" }
      let(:to) { "2019/1/8" }
      it { is_expected.to be_empty }
    end

    context "2019/1/5 - 2019/1/10" do
      let(:from) { "2019/1/5" }
      let(:to) { "2019/1/10" }
      it { is_expected.to contain_exactly("Jane", "Homu") }

      context "with .within_deleted" do
        subject { EmployeeWithScope.valid_in(from: from, to: to).within_deleted.count }
        it { is_expected.to eq 4 }
      end
    end

    context "2019/1/5 - 2019/1/20" do
      let(:from) { "2019/1/5" }
      let(:to) { "2019/1/20" }
      it { is_expected.to contain_exactly("Jane", "Homu", "Tom", "Mami") }
    end

    context "2019/1/20 - 2019/1/30" do
      let(:from) { "2019/1/20" }
      let(:to) { "2019/1/30" }
      it { is_expected.to contain_exactly("Tom", "Mami", "Kevin", "Mado") }
    end

    context "2019/1/27 - 2019/1/30" do
      let(:from) { "2019/1/27" }
      let(:to) { "2019/1/30" }
      it { is_expected.to contain_exactly("Kevin", "Mado") }
    end
  end

  describe ".without_deleted" do
    include_context "defined records"
    subject { EmployeeWithScope.ignore_valid_datetime.without_deleted.count }

    it { is_expected.to eq 6 }
  end
end
