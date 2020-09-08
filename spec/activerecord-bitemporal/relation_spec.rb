# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "Relation" do
  describe "hook Relation" do
    subject { klass.ancestors }

    context "included ActiveRecord::Bitemporal model" do
      context "`ActiveRecord_Relation`" do
        let(:klass) { Employee.const_get(:ActiveRecord_Relation) }
        it { is_expected.to include ActiveRecord::Bitemporal::Relation }
      end
    end
  end

  describe ".all" do
    subject { Employee.all }
    before do
      (1..5).each { |i| Employee.create!(name: "Employee#{i}") }
      Employee.first.update(name: "Tom")
      Employee.second.update(name: "Tom")
      Employee.third.update(name: "Tom")
      Employee.third.update(name: "Jane")
    end
    it { is_expected.to have_attributes count: 5 }
    it do
      Timecop.freeze(Time.utc(2018, 12, 25).in_time_zone) {
        expect(subject.to_sql).to match %r/"employees"."valid_from" <= '2018-12-25 00:00:00' AND "employees"."valid_to" > '2018-12-25 00:00:00'/
        expect(subject.arel.to_sql).to match %r/"employees"."transaction_from" <= \$1 AND "employees"."transaction_to" > \$2/
        expect(subject.arel.to_sql).to match %r/"employees"."valid_from" <= \$3 AND "employees"."valid_to" > \$4/
      }
    end

    context "when creating" do
      let(:count) { -> { Employee.all.count } }
      subject { -> { Employee.create!(name: "Homu") } }
      it { is_expected.to change(&count).by(1) }
    end

    context "when updating" do
      let(:count) { -> { Employee.all.count } }
      subject { -> { Employee.first.update(name: "Homu") } }
      it { is_expected.not_to change(&count) }
    end

    context "when destroying" do
      let(:count) { -> { Employee.all.count } }
      subject { -> { Employee.first.destroy } }
      it { is_expected.to change(&count).by(-1) }
    end
  end

  describe ".pluck" do
    let(:columns) { [] }
    let(:create_time) { Time.current }
    let(:prefix) { Employee.first.id - 1 }
    subject { Employee.pluck(*columns) }
    before do
      (1..5).each { |i| Employee.create!(name: "Employee#{i}") }
      Employee.first.update(name: "Tom")
      Employee.second.update(name: "Tom")
      Employee.third.update(name: "Tom")
      Employee.third.update(name: "Jane")
    end
    context "`:id` and `:bitemporal_id`" do
      let(:columns) { [:id, :bitemporal_id] }
      it { is_expected.to contain_exactly(*[[4, 4], [5, 5], [7, 1], [9, 2], [13, 3]].map { |it| it.map(&prefix.method(:+)) }) }
    end
  end

  describe ".where" do
    subject { Employee.where(name: "Tom") }
    before do
      (1..5).each { |i| Employee.create!(name: "Employee#{i}") }
      Employee.first.update(name: "Tom")
      Employee.second.update(name: "Tom")
      Employee.third.update(name: "Tom")
      Employee.third.update(name: "Jane")
    end
    it { is_expected.to have_attributes count: 2 }
    it do
      Timecop.freeze(Time.utc(2018, 12, 25).in_time_zone) {
        expect(subject.to_sql).to match %r/"employees"."valid_from" <= '2018-12-25 00:00:00' AND "employees"."valid_to" > '2018-12-25 00:00:00'/
        expect(subject.arel.to_sql).to match %r/"employees"."valid_from" <= \$3 AND "employees"."valid_to" > \$4/
      }
    end

    context "update `name` to `Jane`" do
      before { Employee.create!(name: "Tom") }
      let(:count) { -> { Employee.where(name: "Tom").count } }
      subject { -> { Employee.find_by(name: "Tom").update(name: "Jane") } }
      it { is_expected.to change(&count).by(-1) }
    end

    context "update `name` to `Tom`" do
      before { Employee.create!(name: "Tom") }
      let(:count) { -> { Employee.where(name: "Tom").count } }
      subject { -> { Employee.where.not(name: "Tom").first.update(name: "Tom") } }
      it { is_expected.to change(&count).by(1) }
    end
  end

  describe ".count" do
    subject { Employee }
    before do
      (1..3).each { |i| Employee.create!(name: "Employee#{i}") }
    end
    it { is_expected.to have_attributes count: 3 }

    context "update `name`" do
      let(:count) { -> { Employee.count } }
      subject { -> { Employee.first.update(name: "Tom") } }
      it { is_expected.not_to change(&count) }
    end

    context "force_update `valid_to`" do
      let(:count) { -> { Employee.count } }
      subject { -> { Employee.first.force_update { |it| it.update(valid_to: Time.current) } } }
      it { is_expected.to change(&count).by(-1) }
    end
  end

  describe ".exists?" do
    context "with `valid_at" do
      before do
        Timecop.freeze("2019/1/10") { Company.create! }
      end
      subject { Company.valid_at(valid_at).exists? }
      context "`valid_at` is before create" do
        let(:valid_at) { "2019/1/5" }
        it { is_expected.to be_falsey }
      end
      context "`valid_at` is after create" do
        let(:valid_at) { "2019/1/15" }
        it { is_expected.to be_truthy }
      end
    end
  end

  describe ".merge" do
    let(:relation) { Company.valid_at("2019/1/1").merge(Company.valid_at("2019/2/2")) }
    subject { relation.bitemporal_option }
    it { is_expected.to include(valid_datetime: "2019/2/2".in_time_zone) }
    it { expect(relation.loaded?).to be_falsey }
    it do
      puts relation.to_sql
      puts relation.arel.to_sql
      pp subject
    end
  end

  describe "preload" do
    let(:company_relation) { Company.valid_at("2019/1/5").where(bitemporal_id: @company.id) }
    let(:employee) { company.employees.first }
    let(:address)  { employee.address }
    before do
      @company = nil
      address = Timecop.freeze("2018/5/1") { Address.create(name: "Address1") }
      Timecop.freeze("2019/1/1") do
        @company = Company.create(name: "Company1")
        @company.employees.create(name: "Employee1")
        @company.employees.first.address = address
      end

      Timecop.freeze("2019/1/10") do
        @company.update(name: "Company2")
        @company.employees.first.update(name: "Employee2")
        @company.employees.first.address.update(name: "Address2")
      end
    end

    context ".includes" do
      let(:company) { company_relation.includes(*associations).first }
      context "associations is `:employees`" do
        let(:associations) { [:employees] }
        it { expect(employee).to have_attributes(name: "Employee1") }
        it { expect(address).to have_attributes(name: "Address1") }
      end
      context "associations is `employees, { employees: :address }`" do
        let(:associations) { [:employees, { employees: :address }] }
        it { expect(employee).to have_attributes(name: "Employee1") }
        it { expect(address).to have_attributes(name: "Address1") }
      end
      context "associations is `employees, { employees: [:address] }`" do
        let(:associations) { [:employees, { employees: [:address] }] }
        it { expect(employee).to have_attributes(name: "Employee1") }
        it { expect(address).to have_attributes(name: "Address1") }
      end
    end

    context ".includes.includes" do
      let(:company) { company_relation.includes(:employees).includes(employees: :address).first }
      it { expect(employee).to have_attributes(name: "Employee1") }
      it { expect(address).to have_attributes(name: "Address1") }
    end

    context ".eager_load" do
      let(:company) { company_relation.eager_load(:employees, employees: :address).first }
      it { expect(employee).to have_attributes(name: "Employee1") }
      it { expect(address).to have_attributes(name: "Address1") }
    end

    context ".joins" do
      let(:company) { company_relation.joins(:employees, employees: :address).first }
      it { expect(employee).to have_attributes(name: "Employee1") }
      it { expect(address).to have_attributes(name: "Address1") }
    end

    context ".preload" do
      let(:company) { company_relation.preload(:employees, employees: :address).first }
      it { expect(employee).to have_attributes(name: "Employee1") }
      it { expect(address).to have_attributes(name: "Address1") }
    end

    context ".joins.left_joins" do
      let(:company) { company_relation.joins(:employees).left_joins(:employees) }
      it { expect(company.count).to eq(1) }
    end
  end

  context ".left_joins" do
    describe "using table name alias for multiple join" do
      let!(:company) { Company.create(name: "Company") }
      let!(:employee) { company.employees.create(name: "Jane").tap { |m| m.update(name: "Tom") } }

      it 'returns a record' do
        expect(Company.joins(:employees).left_joins(:employees).where(employees: { bitemporal_id: employee.id }).count).to eq(1)
      end
    end
  end
end
