# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "transaction_at" do
  describe "fix `transaction_from` and `transaction_to`" do
    let(:company) { Company.create(name: "Company1") }
    define_method(:company_all) { Company.ignore_valid_datetime.within_deleted.bitemporal_for(company.id).order(:transaction_from) }

    before do
      # Created any records
      company.update!(name: "Company2")
      company.force_update { |it| it.update!(name: "Company3") }
    end

    context "updated" do
      it "prev.transaction_to to equal next.transaction_from" do
        company.update!(name: "NewCompany")
        expect(company_all[-3].transaction_to).to eq(company_all[-2].transaction_from)
                                         .and(eq(company_all[-1].transaction_from))
      end

      it "updated `transaction_from`" do
        expect { company.update(name: "Company4").to change { company.transaction_from } }
      end

      context "with `#force_update`" do
        it do
          company.force_update { |it| it.update!(name: "NewCompany") }
          expect(company_all[-2].transaction_to).to eq(company_all[-1].transaction_from)
        end
      end
    end

    context "deleted" do
      it do
        company.reload.destroy
        expect(company_all[-2].transaction_to).to eq(company_all[-1].transaction_from)
      end
    end
  end

  describe ".create" do
    let(:_01_01) { "2020/01/01".to_time }
    let(:_04_01) { "2020/04/01".to_time }
    let(:_08_01) { "2020/08/01".to_time }
    let(:_12_01) { "2020/12/01".to_time }
    let(:time_current) { Time.current.round(6) }
    subject { Company.create(params) }

    context "params is empty" do
      let(:params) { {} }
      it { is_expected.to have_attributes(
        created_at: subject.transaction_from,
        transaction_from: subject.created_at,
        valid_from: subject.transaction_from,
        deleted_at: nil,
        transaction_to: ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO
      ) }
    end

    context "set `created_at`" do
      let(:params) { { created_at: _01_01 } }
      it { is_expected.to have_attributes(
        created_at: _01_01,
        transaction_from: _01_01,
        deleted_at: nil,
        transaction_to: ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO
      ) }
    end
    context "set `transaction_from`" do
      let(:params) { { transaction_from: _01_01 } }
      it { is_expected.to have_attributes(
        created_at: _01_01,
        transaction_from: _01_01,
        deleted_at: nil,
        transaction_to: ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO
      ) }
    end
    context "set `created_at` and `transaction_from`" do
      let(:params) { { created_at: _01_01, transaction_from: _04_01 } }
      it { is_expected.to have_attributes(
        created_at: _01_01,
        transaction_from: _01_01,
        deleted_at: nil,
        transaction_to: ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO
      ) }
    end

    context "set `valid_from`" do
      let(:params) { { valid_from: _01_01 } }
      it { is_expected.to have_attributes(
        created_at: subject.transaction_from,
        transaction_from: subject.created_at,
        valid_from: _01_01,
        deleted_at: nil,
        transaction_to: ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO
      ) }
    end
    context "set `valid_from` and `transaction_from`" do
      let(:params) { { valid_from: _01_01, transaction_from: _04_01 } }
      it { is_expected.to have_attributes(
        created_at: _04_01,
        transaction_from: _04_01,
        valid_from: _01_01,
        deleted_at: nil,
        transaction_to: ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO
      ) }
    end
    context "set `valid_from`, `created_at` and `transaction_from`" do
      let(:params) { { valid_from: _01_01, created_at: _08_01, transaction_from: _04_01 } }
      it { is_expected.to have_attributes(
        created_at: _08_01,
        transaction_from: _08_01,
        valid_from: _01_01,
        deleted_at: nil,
        transaction_to: ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO
      ) }
    end

    context "set `deleted_at`" do
      let(:params) { { deleted_at: _01_01 } }
      it { is_expected.to have_attributes(
        created_at: subject.transaction_from,
        transaction_from: subject.created_at,
        deleted_at: _01_01,
        transaction_to: _01_01
      ) }

      context "to `nil`" do
        let(:params) { { deleted_at: nil } }
        it { is_expected.to have_attributes(
          created_at: subject.transaction_from,
          transaction_from: subject.created_at,
          deleted_at: nil,
          transaction_to: ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO
        ) }
      end

      context
    end
    context "set `transaction_to`" do
      let(:params) { { transaction_to: _01_01 } }
      it { is_expected.to have_attributes(
        created_at: subject.transaction_from,
        transaction_from: subject.created_at,
        deleted_at: _01_01,
        transaction_to: _01_01
      ) }
    end
    context "set `deleted_at` and `transaction_to`" do
      let(:params) { { deleted_at: _01_01, transaction_to: _04_01 } }
      it { is_expected.to have_attributes(
        created_at: subject.transaction_from,
        transaction_from: subject.created_at,
        deleted_at: _01_01,
        transaction_to: _01_01
      ) }

      context "`deleted_at` to `nil`" do
        let(:params) { { deleted_at: nil, transaction_to: _04_01  } }
        it { is_expected.to have_attributes(
        created_at: subject.transaction_from,
        transaction_from: subject.created_at,
          deleted_at: _04_01,
          transaction_to: _04_01
        ) }
      end
    end
  end

  describe "#update" do
    let(:company) { Company.create(name: "Company1") }
    define_method(:company_all) { Company.ignore_valid_datetime.within_deleted.bitemporal_for(company.id).order(:transaction_from) }

    context "some updates" do
      before do
        (2..5).each { |i|
          company.update(name: "Company#{i}")
        }
      end
      it do
        expect(company_all.pluck(:created_at, :transaction_from).map { |a, b| a == b }).to be_all(true)
      end
      it do
        expect(company_all.pluck(:deleted_at, :transaction_to).map { |a, b| b == ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO || a == b }).to be_all(true)
      end
    end

    context "some force updates" do
      before do
        (2..5).each { |i|
          company.name = "Company#{i}"
          company.force_update(&:save!)
        }
      end
      it do
        expect(company_all.pluck(:created_at, :transaction_from).map { |a, b| a == b }).to be_all(true)
      end
      it do
        expect(company_all.pluck(:deleted_at, :transaction_to).map { |a, b| b == ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO || a == b }).to be_all(true)
      end
    end

    context "destroyed" do
      before do
        company.destroy!
      end
      it do
        expect(company_all.pluck(:created_at, :transaction_from).map { |a, b| a == b }).to be_all(true)
      end
      it do
        expect(company_all.pluck(:deleted_at, :transaction_to).map { |a, b| b == ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO || a == b }).to be_all(true)
      end
    end

    context "some updates" do
      before do
        (2..5).each { |i|
          company.update(name: "Company#{i}")
        }
      end
      it do
        companies = Company.ignore_valid_datetime.within_deleted.bitemporal_for(company.bitemporal_id)
        expect(companies.pluck(:created_at, :transaction_from).map { |a, b| a == b }).to be_all(true)
      end
    end

    context "some force updates" do
      before do
        (2..5).each { |i|
          company.name = "Company#{i}"
          company.force_update(&:save!)
        }
      end
      it do
        companies = Company.ignore_valid_datetime.within_deleted.bitemporal_for(company.bitemporal_id)
        expect(companies.pluck(:created_at, :transaction_from).map { |a, b| a == b }).to be_all(true)
      end
    end

    context "destroyed" do
      before do
        company.destroy!
      end
      it do
        companies = Company.ignore_valid_datetime.within_deleted.bitemporal_for(company.bitemporal_id)
        expect(companies.pluck(:created_at, :transaction_from).map { |a, b| a == b }).to be_all(true)
      end
    end

    context "before valid_from" do
      let(:created_at) { 3.days.ago.round(6) }
      let(:company) { Timecop.freeze(created_at) { Company.create(name: "Company1") } }
      let(:updated_at) { created_at + 1.days }
      let(:valid_datetime) { company.valid_from - 1.days }
      subject { -> {
        Timecop.freeze(updated_at) {
          ActiveRecord::Bitemporal.valid_at(valid_datetime) {
            company.update(name: "Comapny2")
          }
        }
      } }
      it do
        is_expected.to change { Company.ignore_valid_datetime.bitemporal_for(company.id).order(:transaction_from).pluck(:transaction_from) }.to match [created_at, updated_at]
      end
    end
  end

  describe "validation `transaction_from` `transaction_to`" do
    let(:time_current) { Time.current.round(6) }
    subject { employee }
    context "with `transaction_from` and `transaction_to`" do
      let(:employee) { Employee.new(name: "Jane", transaction_from: transaction_from, transaction_to: transaction_to) }
      context "`transaction_from` < `transaction_to`" do
        let(:transaction_from) { time_current }
        let(:transaction_to) { transaction_from + 10.days }
        it { is_expected.to be_valid }
      end

      context "`transaction_from` > `transaction_to`" do
        let(:transaction_from) { transaction_to + 10.days }
        let(:transaction_to) { time_current }
        it { is_expected.to be_invalid }
      end

      context "`transaction_from` == `transaction_to`" do
        let(:transaction_from) { time_current }
        let(:transaction_to) { transaction_from }
        it { is_expected.to be_invalid }
      end

      context "`transaction_from` is `nil`" do
        let(:transaction_from) { nil }
        let(:transaction_to) { time_current }
        it { is_expected.to be_invalid }
      end

      context "`transaction_to` is `ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO`" do
        let(:transaction_from) { time_current }
        let(:transaction_to) { ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO }
        it { is_expected.to be_valid }
      end

      context "`transaction_from` and `transaction_to` is `ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO`" do
        let(:transaction_from) { nil }
        let(:transaction_to) { ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO }
        it { is_expected.to be_invalid }
      end
    end

    context "with `transaction_from`" do
      let(:employee) { Employee.new(name: "Jane", transaction_from: transaction_from) }
      let(:transaction_from) { time_current }
      it { is_expected.to be_valid }
    end

    context "with `transaction_to`" do
      let(:employee) { Employee.new(name: "Jane", transaction_to: transaction_to) }
      let(:transaction_to) { time_current + 10.days }
      it { is_expected.to be_valid }
    end

    context "blank `transaction_from` and `transaction_to`" do
      let(:employee) { Employee.new(name: "Jane") }
      it { is_expected.to be_valid }
    end

    context "with `bitemporal_id`" do
      let!(:employee0) { Employee.create!(name: "Jane") }
      subject { Employee.new(name: "Jane", bitemporal_id: employee0.bitemporal_id).save }
      it { is_expected.to be_falsey }
    end
  end

  describe "uniqueness" do
    class EmployeeWithUniquness < Employee
      validates :name, uniqueness: true
    end

    let(:time_current) { Time.current.round(6) }
    context "have an active model" do
      shared_context "define active model" do
        let(:active_from) { time_current }
        let(:active_to) { active_from + 10.days }
        let(:valid_from) { "2019/01/01".to_time }
        let(:valid_to) { "2019/12/31".to_time }
        before do
          EmployeeWithUniquness.create!(name: "Jane", transaction_from: active_from, transaction_to: active_to, valid_from: valid_from, valid_to: valid_to)
        end
      end

      shared_examples "valid uniqueness" do
        include_context "define active model"
        subject { EmployeeWithUniquness.new(name: "Jane", transaction_from: new_from, transaction_to: new_to, valid_from: valid_from, valid_to: valid_to) }
        it { is_expected.to be_valid }
      end

      shared_examples "invalid uniqueness" do
        include_context "define active model"
        subject { EmployeeWithUniquness.new(name: "Jane", transaction_from: new_from, transaction_to: new_to, valid_from: valid_from, valid_to: valid_to) }
        it { is_expected.to be_invalid }
      end

      # active transaction time :                 |<---------->|
      # new transaction time    : |<---------->|
      it_behaves_like "valid uniqueness" do
        let(:new_from) { active_from - 12.days }
        let(:new_to) { active_to - 12.days }
      end

      # active transaction time :              |<---------->|
      # new transaction time    : |<---------->|
      it_behaves_like "valid uniqueness" do
        let(:new_from) { new_to - 10.days }
        let(:new_to) { active_from }
      end

      # active transaction time :        |<---------->|
      # new transaction time    : |<---------->|
      it_behaves_like "invalid uniqueness" do
        let(:new_from) { active_from - 5.days }
        let(:new_to) { active_to - 5.days }
      end

      # active transaction time :        |<---------->|
      # new transaction time    : |<----------------->|
      it_behaves_like "invalid uniqueness" do
        let(:new_from) { active_from - 15.days }
        let(:new_to) { active_to }
      end

      # active : |<---------->|
      # new    : |<---------->|
      it_behaves_like "invalid uniqueness" do
        let(:new_from) { active_from }
        let(:new_to) { active_to }
      end

      # active : |<---------->|
      # new    :   |<------>|
      it_behaves_like "invalid uniqueness" do
        let(:new_from) { active_from + 2.days }
        let(:new_to) { active_to - 2.days }
      end

      # active :   |<---------->|
      # new    : |<-------------->|
      it_behaves_like "invalid uniqueness" do
        let(:new_from) { active_from - 2.days }
        let(:new_to) { active_to + 2.days }
      end

      # active transaction time : |<---------->|
      # new transaction time    : |<----------------->|
      it_behaves_like "invalid uniqueness" do
        let(:new_from) { active_from }
        let(:new_to) { active_to + 15.days }
      end

      # active transaction time : |<---------->|
      # new transaction time    :        |<---------->|
      it_behaves_like "invalid uniqueness" do
        let(:new_from) { active_from + 5.days }
        let(:new_to) { active_to + 5.days }
      end

      # active transaction time : |<---------->|
      # new transaction time    :              |<---------->|
      it_behaves_like "valid uniqueness" do
        let(:new_from) { active_to }
        let(:new_to) { new_from + 10.days }
      end

      # active transaction time : |<---------->|
      # new transaction time    :                 |<---------->|
      it_behaves_like "valid uniqueness" do
        let(:new_from) { active_from + 12.days }
        let(:new_to) { active_to + 12.days }
      end

      # active transaction time :        |<---------->|
      # new transaction time    : |<-----------------------> Infinite
      it_behaves_like "invalid uniqueness" do
        let(:new_from) { active_from - 5.days }
        let(:new_to) { ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO }
      end

      # active transaction time : |<-----------------------> Infinite
      # new transaction time    :        |<---------->|
      it_behaves_like "invalid uniqueness" do
        let(:new_from) { active_from + 5.days }
        let(:new_to) { new_from + 5.days }
        let(:active_to) { ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO }
      end

      # active transaction time : |<-----------------------> Infinite
      # new transaction time    :        |<-----------------------> Infinite
      it_behaves_like "invalid uniqueness" do
        let(:new_from) { active_from + 5.days }
        let(:new_to) { nil }
        let(:active_to) { ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO }
      end
    end

    context "have an active models" do
      shared_context "define active models" do
        let(:active1_from) { time_current }
        let(:active1_to) { active1_from + 10.days }

        let(:active2_from) { active1_from + 40.days }
        let(:active2_to) { active2_from + 10.days }

        before do
          EmployeeWithUniquness.create!(name: "Jane", transaction_from: active1_from, transaction_to: active1_to)
          EmployeeWithUniquness.create!(name: "Jane", transaction_from: active2_from, transaction_to: active2_to)
        end
      end

      shared_examples "valid uniqueness" do
        include_context "define active models"
        subject { EmployeeWithUniquness.new(name: "Jane", transaction_from: new_from, transaction_to: new_to) }
        it { is_expected.to be_valid }
      end

      shared_examples "invalid uniqueness" do
        include_context "define active models"
        subject { EmployeeWithUniquness.new(name: "Jane", transaction_from: new_from, transaction_to: new_to) }
        it { is_expected.to be_invalid }
      end

      # active1 transaction time : |<---------->|
      # active2 transaction time :                                 |<---------->|
      # new transaction time     :                 |<---------->|
      it_behaves_like "valid uniqueness" do
        let(:new_from) { active1_to + 2.days }
        let(:new_to) { new_from + 10.days }
      end

      # active1 transaction time :                 |<---------->|
      # active2 transaction time :                                 |<---------->|
      # new transaction time     : |<---------->|
      it_behaves_like "valid uniqueness" do
        let(:new_from) { new_to - 10.days }
        let(:new_to) { active1_from - 2.days }
      end

      # active1 transaction time : |<---------->|
      # active2 transaction time :                |<---------->|
      # new transaction time     :                               |<---------->|
      it_behaves_like "valid uniqueness" do
        let(:new_from) { active2_to + 2.days }
        let(:new_to) { new_from + 10.days }
      end

      # active1 transaction time : |<---------->|
      # active2 transaction time :          |<---------->|
      # new transaction time     :                    |<---------->|
      it_behaves_like "invalid uniqueness" do
        let(:new_from) { active1_to - 2.days }
        let(:new_to) { active2_from + 2.days }
      end

      # active1 transaction time : |<---------->|
      # active2 transaction time :              |<---------->|
      # new transaction time     :                           |<---------->|
      it_behaves_like "valid uniqueness" do
        let(:new_from) { active2_to }
        let(:new_to) { new_from + 10.days }
      end
    end

    describe ".create" do
      subject { -> { EmployeeWithUniquness.create!(name: "Tom") } }
      context "exists destroyed model" do
        let(:employee) { EmployeeWithUniquness.create!(name: "Jane").tap { |it| it.update(name: "Tom") } }
        before do
          employee.destroy!
        end
        it { is_expected.not_to raise_error }
      end

      context "exists past model" do
        before do
          EmployeeWithUniquness.create!(name: "Tom", transaction_from: "1982/12/02", transaction_to: "2001/03/24")
        end
        it { is_expected.not_to raise_error }
      end

      context "exists future model" do
        before do
          EmployeeWithUniquness.create!(name: "Tom", transaction_from: Time.current + 10.days)
        end
        it { is_expected.to raise_error ActiveRecord::RecordInvalid }
      end
    end

    context "`valid_datetime` out of range `valid_from` ~ `valid_to`" do
      it { is_expected.to be_truthy }

      context "empty records" do
        before { EmployeeWithUniquness.destroy_all }
        subject { EmployeeWithUniquness.new(valid_from: "9999/1/10").valid_at("9999/1/1", &:save) }
        it { is_expected.to be_truthy }
      end
    end

    context "duplicated `valid_from` `valid_to` with non set `transaction_from`" do
      let(:transaction_from) { "2019/04/01".to_time }
      let(:transaction_to) { "2019/10/01".to_time }
      let(:valid_from) { "2019/01/01".to_time }
      let(:valid_to) { "2019/06/01".to_time }
      before do
        EmployeeWithUniquness.create!(transaction_from: transaction_from, transaction_to: transaction_to, valid_from: valid_from, valid_to: valid_to, name: "Jane")
      end

      context "current time in transaction_from ~ transaction_to" do
        it do
          Timecop.freeze(transaction_from + 1.days) {
            emp = EmployeeWithUniquness.new(valid_from: valid_from, valid_to: valid_to, name: "Jane")
            expect(emp).to be_invalid
          }
        end
      end

      context "current time greater than transaction_to" do
        it do
          Timecop.freeze(transaction_from + 1000.days) {
            emp = EmployeeWithUniquness.new(valid_from: valid_from, valid_to: valid_to, name: "Jane")
            expect(emp).to be_valid
          }
        end
      end
    end

    context "Update with duplicate name after update" do
      it do
        company1 = EmployeeWithUniquness.create!(name: "Jane")
        company2 = EmployeeWithUniquness.create!(name: "Tom")
        company1.update!(name: "Homu")
        expect { company2.update!(name: "Jane") }.not_to raise_error
      end
    end
  end

  xdescribe "without created_at deleted_at" do
    ActiveRecord::Schema.define(version: 1) do
      create_table :without_created_at_deleted_ats, force: true do |t|
        t.string :name
        t.integer :bitemporal_id
        t.datetime :valid_from
        t.datetime :valid_to
        t.datetime :transaction_from
        t.datetime :transaction_to
      end
    end
    class WithoutCreatedAtDeletedAt < ActiveRecord::Base
      include ActiveRecord::Bitemporal
    end

    context "create" do
      subject { -> { WithoutCreatedAtDeletedAt.create!(name: "Tom") } }
      it { is_expected.not_to raise_error }

      context "with transaction_to" do
        subject { -> { WithoutCreatedAtDeletedAt.create!(name: "Tom", transaction_to: Time.current + 10.days) } }
        it { is_expected.not_to raise_error }
      end
    end

    context "update" do
      let(:record) { WithoutCreatedAtDeletedAt.create!(name: "Tom") }
      subject { -> { record.update(name: "Jane") } }
      it { is_expected.not_to raise_error }
    end

    context "force_update" do
      let(:record) { WithoutCreatedAtDeletedAt.create!(name: "Tom") }
      subject { -> { record.force_update { |record| record.update(name: "Jane") } } }
      it { is_expected.not_to raise_error }
    end

    context "destroy" do
      let(:record) { WithoutCreatedAtDeletedAt.create!(name: "Tom") }
      subject { -> { record.destroy! } }
      it { is_expected.not_to raise_error }
    end
  end
end
