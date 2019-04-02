require 'spec_helper'

class EmployeeWithScope < Employee
  include ActiveRecord::Bitemporal::Scope::Extention
  include ActiveRecord::Bitemporal::Scope::Experimental
end

RSpec.describe ActiveRecord::Bitemporal::Scope do
  describe ".within_deleted" do
    before do
      EmployeeWithScope.create!(name: "Kevin").update(name: "Jane")
    end
    subject { EmployeeWithScope.ignore_valid_datetime.within_deleted.count }
    it { is_expected.to eq 3 }
  end

  describe ".without_deleted" do
    before do
      EmployeeWithScope.create!(name: "Kevin").update(name: "Jane")
    end
    subject { EmployeeWithScope.ignore_valid_datetime.within_deleted.without_deleted.count }
    it { is_expected.to eq 2 }
  end

  describe ActiveRecord::Bitemporal::Scope::Extention do
    describe ".bitemporal_histories_by" do
      let(:employee) { EmployeeWithScope.create!(name: "Jane") }
      before do
        employee.update(name: "Tom")
        employee.update(name: "Jane")
        EmployeeWithScope.create!(name: "Kevin").update(name: "Jane")
      end
      subject { EmployeeWithScope.bitemporal_histories_by(employee.id) }
      it { expect(subject.count).to eq 3 }
      it { expect(subject.where(name: "Jane").count).to eq 2 }
      it { expect(subject.ids).to eq [employee.id, employee.id, employee.id] }
    end

    describe ".bitemporal_latest_by" do
      let(:employee) { EmployeeWithScope.create!(name: "Jane") }
      before do
        employee.update(name: "Tom")
        employee.update(name: "Jane")
        EmployeeWithScope.create!(name: "Jane").update(name: "Kevin")
      end
      subject { EmployeeWithScope.bitemporal_latest_by(employee.id) }
      it { expect(subject).to be_kind_of EmployeeWithScope }
      it { expect(subject.id).to eq employee.id }
      it { expect(subject.name).to eq "Jane" }
    end

    describe ".bitemporal_oldest_by" do
      let(:employee) { EmployeeWithScope.create!(name: "Jane") }
      before do
        employee.update(name: "Tom")
        employee.update(name: "Jane")
        EmployeeWithScope.create!(name: "Jane").update(name: "Kevin")
      end
      subject { EmployeeWithScope.bitemporal_oldest_by(employee.id) }
      it { expect(subject).to be_kind_of EmployeeWithScope }
      it { expect(subject.id).to eq employee.id }
      it { expect(subject.name).to eq "Jane" }
    end
  end

  describe ActiveRecord::Bitemporal::Scope::Experimental do
    shared_examples "defined records" do
      before do
        emp1 = nil
        emp2 = nil
        Timecop.freeze("2019/1/10") {
          emp1 = EmployeeWithScope.create!(name: "Jane")
          emp2 = EmployeeWithScope.create!(name: "Homu")
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
  end
end
