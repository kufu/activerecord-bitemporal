# frozen_string_literal: true

require 'spec_helper'

class EmployeeWithScope < Employee
  include ActiveRecord::Bitemporal::Scope::Extension
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

  describe ".bitemporal_for" do
    let(:employee) { Employee.create!(name: "Jane") }
    before do
      Employee.create!
      Employee.create!
      Employee.create!
      employee.update(name: "Tom")
      employee.update(name: "Kevin")
    end
    subject { Employee.ignore_valid_datetime.bitemporal_for(employee.id) }
    it { expect(subject.count).to eq 3 }
  end

  describe ".valid_in" do
    before do
      emp1 = nil
      emp2 = nil
      Timecop.freeze("2019/1/10") {
        emp1 = Employee.create!(name: "Jane")
        emp2 = Employee.create!(name: "Homu")
      }

      Timecop.freeze("2019/1/20") {
        emp1.update!(name: "Tom")
        emp2.update!(name: "Mami")
      }

      Timecop.freeze("2019/1/30") {
        emp1.update!(name: "Kevin")
        emp2.update!(name: "Mado")
      }
    end

    subject { Employee.valid_in(from: from, to: to).pluck(:name).flatten }

    context "2019/1/5 - 2019/1/25" do
      let(:from) { "2019/1/5" }
      let(:to) { "2019/1/25" }
      it { is_expected.to contain_exactly("Jane", "Homu", "Tom", "Mami") }
    end

    context "2019/1/15 - 2019/2/1" do
      let(:from) { "2019/1/15" }
      let(:to) { "2019/2/1" }
      it { is_expected.to contain_exactly("Jane", "Homu", "Tom", "Mami", "Kevin", "Mado") }
    end

    context "2019/1/20 - 2019/1/30" do
      let(:from) { "2019/1/20" }
      let(:to) { "2019/1/30" }
      it { is_expected.to contain_exactly("Homu", "Jane", "Mami", "Tom", "Kevin", "Mado") }
    end

    describe ".to_sql" do
      before do
        @old_time_zone = Time.zone
        Time.zone = "Tokyo"
      end
      after { Time.zone = @old_time_zone }
      let(:from) { "2019/1/20" }
      let(:to) { "2019/1/30" }
      subject { Employee.valid_in(from: from, to: to).to_sql }
      it { is_expected.to match %r/"employees"."valid_to" >= '2019-01-19 15:00:00'/ }
      it { is_expected.to match %r/"employees"."valid_from" <= '2019-01-29 15:00:00'/ }
    end

    describe ".arel.to_sql" do
      let(:from) { "2019/1/20" }
      let(:to) { "2019/1/30" }
      subject { Employee.valid_in(from: from, to: to).arel.to_sql }
      it { is_expected.to match %r/"employees"."valid_to" >= \$3/ }
      it { is_expected.to match %r/"employees"."valid_from" <= \$4/ }
    end
  end

  describe ".valid_allin" do
    before do
      emp1 = nil
      emp2 = nil
      Timecop.freeze("2019/1/10") {
        emp1 = Employee.create!(name: "Jane")
        emp2 = Employee.create!(name: "Homu")
      }

      Timecop.freeze("2019/1/20") {
        emp1.update!(name: "Tom")
        emp2.update!(name: "Mami")
      }

      Timecop.freeze("2019/1/30") {
        emp1.update!(name: "Kevin")
        emp2.update!(name: "Mado")
      }
    end

    subject { Employee.valid_allin(from: from, to: to).pluck(:name).flatten }

    context "2019/1/5 - 2019/1/15" do
      let(:from) { "2019/1/5" }
      let(:to) { "2019/1/15" }
      it { is_expected.to be_empty }
    end

    context "2019/1/5 - 2019/1/25" do
      let(:from) { "2019/1/5" }
      let(:to) { "2019/1/25" }
      it { is_expected.to contain_exactly("Jane", "Homu") }
    end

    context "2019/1/10 - 2019/1/20" do
      let(:from) { "2019/1/10" }
      let(:to) { "2019/1/20" }
      it { is_expected.to contain_exactly("Jane", "Homu") }
    end

    context "2019/1/10 - 2019/1/21" do
      let(:from) { "2019/1/10" }
      let(:to) { "2019/1/21" }
      it { is_expected.to contain_exactly("Jane", "Homu") }
    end

    context "2019/1/15 - 2019/2/1" do
      let(:from) { "2019/1/15" }
      let(:to) { "2019/2/1" }
      it { is_expected.to contain_exactly("Tom", "Mami") }
    end

    describe ".to_sql" do
      before do
        @old_time_zone = Time.zone
        Time.zone = "Tokyo"
      end
      after { Time.zone = @old_time_zone }
      let(:from) { "2019/1/20" }
      let(:to) { "2019/1/30" }
      subject { Employee.valid_allin(from: from, to: to).to_sql }
      it { is_expected.to match %r/"employees"."valid_from" >= '2019-01-19 15:00:00'/ }
      it { is_expected.to match %r/"employees"."valid_to" <= '2019-01-29 15:00:00'/ }
    end

    describe ".arel.to_sql" do
      let(:from) { "2019/1/20" }
      let(:to) { "2019/1/30" }
      subject { Employee.valid_allin(from: from, to: to).arel.to_sql }
      it { is_expected.to match %r/"employees"."valid_from" >= \$3/ }
      it { is_expected.to match %r/"employees"."valid_to" <= \$4/ }
    end
  end

  describe ActiveRecord::Bitemporal::Scope::Extension do
    describe ".bitemporal_histories" do
      let(:employee) { EmployeeWithScope.create!(name: "Jane") }
      before do
        employee.update(name: "Tom")
        employee.update(name: "Jane")
        EmployeeWithScope.create!(name: "Kevin").update(name: "Jane")
      end
      subject { EmployeeWithScope.bitemporal_histories(id) }

      context "valid `id`" do
        let(:id) { employee.id }
        it { expect(subject.pluck(:name)).to contain_exactly("Jane", "Tom", "Jane") }
        it { expect(subject.where(name: "Jane").count).to eq 2 }
        it { expect(subject.ids).to eq [employee.id, employee.id, employee.id] }
      end

      context "invalid `id`" do
        let(:id) { -1 }
        it { is_expected.to be_empty }
      end
    end

    describe ".bitemporal_most_future" do
      let(:employee) { EmployeeWithScope.create!(name: "Jane") }
      before do
        employee.update(name: "Tom")
        employee.update(name: "Jane")
        EmployeeWithScope.create!(name: "Jane").update(name: "Kevin")
      end
      subject { EmployeeWithScope.bitemporal_most_future(id) }

      context "valid `id`" do
        let(:id) { employee.id }
        it { expect(subject).to be_kind_of EmployeeWithScope }
        it { expect(subject.id).to eq employee.id }
        it { expect(subject.name).to eq "Jane" }
        it { expect(subject.transaction_to).to eq ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO }
      end

      context "invalid `id`" do
        let(:id) { -1 }
        it { is_expected.to be_nil }
      end
    end

    describe ".bitemporal_most_past" do
      let(:employee) { EmployeeWithScope.create!(name: "Jane") }
      before do
        employee.update(name: "Tom")
        employee.update(name: "Jane")
        EmployeeWithScope.create!(name: "Jane").update(name: "Kevin")
      end
      subject { EmployeeWithScope.bitemporal_most_past(id) }

      context "valid `id`" do
        let(:id) { employee.id }
        it { expect(subject).to be_kind_of EmployeeWithScope }
        it { expect(subject.id).to eq employee.id }
        it { expect(subject.name).to eq "Jane" }
        it { expect(subject.transaction_to).to eq ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO }
      end

      context "invalid `id`" do
        let(:id) { -1 }
        it { is_expected.to be_nil }
      end
    end
  end
end
