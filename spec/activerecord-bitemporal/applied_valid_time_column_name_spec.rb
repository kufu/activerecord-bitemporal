# frozen_string_literal: true

require 'spec_helper'

ActiveRecord::Schema.define(version: 1) do
  create_table :column_name_applied_companies, force: true do |t|
    t.string :name

    t.integer :bitemporal_id
    t.date :valid_date_from
    t.date :valid_date_to
    t.datetime :deleted_at, precision: 6
    t.datetime :transaction_from, precision: 6
    t.datetime :transaction_to, precision: 6

    t.timestamps
  end
end

class ColumnNameAppliedCompany < ActiveRecord::Base
  bitemporalize valid_from_key: :valid_date_from, valid_to_key: :valid_date_to
end

class ColumnNameAppliedCompanyWithUniqueness < ColumnNameAppliedCompany
  validates :name, uniqueness: true
end

class ColumnNameAppliedCompanyWithScope < ColumnNameAppliedCompany
  include ActiveRecord::Bitemporal::Scope::Extension
  include ActiveRecord::Bitemporal::Scope::Experimental
end

RSpec.describe ActiveRecord::Bitemporal, "applied valid time column name" do
  # NOTE: Use time zone other than UTC
  around { |e| Time.use_zone("Tokyo", &e) }

  describe ".create" do
    context "creating" do
      subject { ColumnNameAppliedCompany.create!(name: "Company") }
      it { expect { subject }.to change(ColumnNameAppliedCompany, :count).by(1) }
    end

    context "created" do
      let(:attributes) { {} }
      subject { ColumnNameAppliedCompany.create!(name: "Company", **attributes) }

      it {
        is_expected.to have_attributes(
          bitemporal_id: subject.id,
          previous_changes: include(
            "id" => [nil, subject.id],
            "valid_date_from" => [nil, Time.zone.today],
            "valid_date_to" => [nil, ActiveRecord::Bitemporal::DEFAULT_VALID_TO.to_date],
            "name" => [nil, "Company"]
          ),
          previously_force_updated?: false
        )
      }
    end
  end

  describe ".find" do
    subject { ColumnNameAppliedCompany.find(target_id) }

    context "exists company" do
      let!(:company) { ColumnNameAppliedCompany.create!(name: "Test") }
      let(:target_id) { company.id }
      it { is_expected.to eq company }
    end

    context "non exists company" do
      let(:target_id) { nil }
      it { expect { subject }.to raise_error(ActiveRecord::RecordNotFound) }
    end
  end

  describe "#update" do
    let(:now) { Time.current.round(6) }
    let(:from) { now.to_date - 1.day }
    let(:to) { now.to_date + 10.days }
    let!(:company) { ColumnNameAppliedCompany.create!(name: "Test1", valid_date_from: from, valid_date_to: to) }

    around { |e| Timecop.freeze(now) { e.run } }

    subject { company.update(name: "Test2") }

    it {
      subject
      actual = ColumnNameAppliedCompany.ignore_valid_datetime.find_by(bitemporal_id: company.id, name: "Test1")
      expect(actual).to have_attributes valid_date_from: from, valid_date_to: now.to_date
    }

    it {
      subject
      actual = ColumnNameAppliedCompany.ignore_valid_datetime.find_by(bitemporal_id: company.id, name: "Test2")
      expect(actual).to have_attributes valid_date_from: now.to_date, valid_date_to: to
    }

    # before:          |-----------|
    # update:  *
    # after:   |-------|
    #                  |-----------|
    context "now time is before" do
      let!(:company) { ColumnNameAppliedCompany.create!(name: "Test", valid_date_from: from, valid_date_to: to) }
      let!(:swapped_id) { company.swapped_id }
      let(:count) { -> { ColumnNameAppliedCompany.where(bitemporal_id: company.id).ignore_valid_datetime.count } }
      let(:valid_date) { from - 1.day }

      subject { company.valid_at(valid_date) { company.update(name: "Test2") } }

      it { expect { subject }.to change(&count).by(1) }
      it { expect { subject }.to change(company, :name).from("Test").to("Test2") }
      it { expect { subject }.to change(company, :swapped_id).from(swapped_id).to(kind_of(Integer)) }
      it { expect { subject }.to change(company, :swapped_id_previously_was).from(nil).to(swapped_id) }
      it {
        subject
        old = ColumnNameAppliedCompany.ignore_valid_datetime.find_by(bitemporal_id: company.id, name: "Test")
        expect(old).to have_attributes valid_date_from: from, valid_date_to: to
      }
      it {
        subject
        current = ColumnNameAppliedCompany.ignore_valid_datetime.find_by(bitemporal_id: company.id, name: "Test2")
        expect(current).to have_attributes valid_date_from: valid_date, valid_date_to: from
      }
    end

    context "failure" do
      context "`valid_datetime` is `company.valid_from`" do
        let!(:company) { ColumnNameAppliedCompany.create!(valid_date_from: "2019/02/01") }
        let(:valid_datetime) { company.valid_date_from }

        subject { company.valid_at(valid_datetime) { |c| c.update(name: "Test") } }

        it { expect { subject }.to raise_error(ActiveRecord::Bitemporal::ValidDatetimeRangeError) }

        context "call `update!`" do
          subject { company.valid_at(valid_datetime) { |c| c.update!(name: "Test") } }

          it { expect { subject }.to raise_error(ActiveRecord::Bitemporal::ValidDatetimeRangeError) }
          it {
            expect { subject }.to raise_error do |e|
              expect(e.message).to eq "valid_date_from #{company.valid_date_from} can't be greater than or equal to valid_date_to #{valid_datetime} " \
                                      "for ColumnNameAppliedCompany with bitemporal_id=#{company.bitemporal_id}"
            end
          }
        end
      end

      context "update for deleted record" do
        let!(:company) {
          Timecop.freeze(now - 2.days) { ColumnNameAppliedCompany.create!(name: "Test1") }
        }

        subject {
          company = ColumnNameAppliedCompany.ignore_bitemporal_datetime.order(:transaction_from).last
          company.update!(name: "Test2")
        }

        before { Timecop.freeze(now - 1.day) { company.destroy } }

        it { expect { subject }.to raise_error(ActiveRecord::RecordNotFound) }
        it {
          expect { subject }.to raise_error do |e|
            expect(e.message).to eq "Update failed: Couldn't find ColumnNameAppliedCompany with 'bitemporal_id'=#{company.bitemporal_id} and 'valid_date_from' > #{now}"
          end
        }
      end
    end
  end

  describe "#destroy" do
    let(:now) { Time.current.round(6) }
    let(:created_time) { now - 3.day }
    let(:updated_time) { now - 2.day }
    let(:destroyed_time) { now - 1.day }
    let!(:company) { Timecop.freeze(created_time) { ColumnNameAppliedCompany.create!(name: "Test") } }
    let(:represent_deleted) { ColumnNameAppliedCompany.find_at_time(updated_time, company.id) }

    subject { Timecop.freeze(destroyed_time) { company.destroy } }

    before do
      Timecop.freeze(updated_time) { company.update!(name: "Test2") }
      @swapped_id_before_destroy = company.swapped_id
    end

    it { expect { subject }.to change(ColumnNameAppliedCompany, :count).by(-1) }
    it { expect { subject }.to change(company, :destroyed?).from(false).to(true) }
    it { expect { subject }.not_to change(company, :valid_date_from) }
    it { expect { subject }.to change(company, :valid_date_to).from(ActiveRecord::Bitemporal::DEFAULT_VALID_TO.to_date).to(destroyed_time.to_date) }
    it { expect { subject }.to change(company, :transaction_from).from(updated_time).to(destroyed_time) }
    it { expect { subject }.not_to change(company, :transaction_to) }
    it { expect { subject }.to change { ColumnNameAppliedCompany.ignore_bitemporal_datetime.count }.by(1) }
    it { expect { subject }.to change(company, :swapped_id).from(@swapped_id_before_destroy).to(kind_of(Integer)) }
    it { expect { subject }.to change(company, :swapped_id_previously_was).from(kind_of(Integer)).to(@swapped_id_before_destroy) }

    it do
      subject
      expect(represent_deleted).to have_attributes(
        valid_date_from: company.valid_date_from,
        valid_date_to: destroyed_time.to_date,
        transaction_to: ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO,
        name: company.name
      )
    end
  end

  describe "ActiveRecord::Bitemporal::Uniqueness" do
    let(:company) { Timecop.freeze("2019/02/01") { ColumnNameAppliedCompanyWithUniqueness.create!(name: "Test") } }

    before do
      Timecop.freeze("2019/03/01") { company.update(name: "Test1") }
    end

    it do
      Timecop.freeze("2019/04/01") { company.valid_at("2019/01/01") { |m|
        m.name = "Test2"
        expect(m).to be_valid
      } }
    end
  end

  describe "ActiveRecord::Bitemporal::Scope" do
    describe ".valid_in" do
      before do
        emp1 = nil
        emp2 = nil
        Timecop.freeze("2019/01/10") {
          emp1 = ColumnNameAppliedCompany.create!(name: "Test1")
          emp2 = ColumnNameAppliedCompany.create!(name: "Test2")
        }

        Timecop.freeze("2019/01/20") {
          emp1.update!(name: "Test1-2")
          emp2.update!(name: "Test2-2")
        }

        Timecop.freeze("2019/01/30") {
          emp1.update!(name: "Test1-3")
          emp2.update!(name: "Test2-3")
        }
      end

      context "2019/01/05 - 2019/01/20" do
        subject { ColumnNameAppliedCompany.valid_in(from: "2019/01/15", to: "2019/01/20").pluck(:name).flatten }
        it { is_expected.to contain_exactly("Test1", "Test2") }
      end

      context "2019/01/05..2019/01/20" do
        subject { ColumnNameAppliedCompany.valid_in("2019/01/05".."2019/01/20").pluck(:name).flatten }
        it { is_expected.to contain_exactly("Test1", "Test2", "Test1-2", "Test2-2") }
      end
    end

    describe ".valid_allin" do
      before do
        emp1 = nil
        emp2 = nil
        Timecop.freeze("2019/01/10") {
          emp1 = ColumnNameAppliedCompany.create!(name: "Test1")
          emp2 = ColumnNameAppliedCompany.create!(name: "Test2")
        }

        Timecop.freeze("2019/01/20") {
          emp1.update!(name: "Test1-2")
          emp2.update!(name: "Test2-2")
        }

        Timecop.freeze("2019/01/30") {
          emp1.update!(name: "Test1-3")
          emp2.update!(name: "Test2-3")
        }
      end

      subject { ColumnNameAppliedCompany.valid_allin(range).pluck(:name).flatten }

      context "2019/01/05..2019/01/30" do
        let(:range) { "2019/01/05".."2019/01/30" }
        it { is_expected.to contain_exactly("Test1", "Test2", "Test1-2", "Test2-2") }
      end

      context "2019/01/05...2019/01/30" do
        let(:range) { "2019/01/05"..."2019/01/30" }
        it {
          expect { subject }.to raise_error do |e|
            expect(e.message).to eq "Range with excluding end is not supported"
          end
        }
      end
    end
  end

  describe "ActiveRecord::Bitemporal::Scope::Extension" do
    let(:now) { Time.zone.today }

    describe ".bitemporal_most_future" do
      let(:company) {
        Timecop.freeze(now - 2.days) { ColumnNameAppliedCompanyWithScope.create!(name: "Test") }
      }

      subject { ColumnNameAppliedCompanyWithScope.bitemporal_most_future(id) }

      before do
        Timecop.freeze(now - 1.day) { company.update(name: "Test2") }
        Timecop.freeze(now) { company.update(name: "Test3") }
      end

      context "valid `id`" do
        let(:id) { company.id }

        it { expect(subject).to be_kind_of ColumnNameAppliedCompanyWithScope }
        it { expect(subject.id).to eq company.id }
        it { expect(subject.name).to eq "Test3" }
        it { expect(subject.transaction_to).to eq ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO }
      end

      context "invalid `id`" do
        let(:id) { -1 }
        it { is_expected.to be_nil }
      end
    end

    describe ".bitemporal_most_past" do
      let(:company) {
        Timecop.freeze(now - 2.days) { ColumnNameAppliedCompanyWithScope.create!(name: "Test") }
      }

      subject { ColumnNameAppliedCompanyWithScope.bitemporal_most_past(id) }

      before do
        Timecop.freeze(now - 1.day) { company.update(name: "Test2") }
        Timecop.freeze(now) { company.update(name: "Test3") }
      end

      context "valid `id`" do
        let(:id) { company.id }

        it { expect(subject).to be_kind_of ColumnNameAppliedCompanyWithScope }
        it { expect(subject.id).to eq company.id }
        it { expect(subject.name).to eq "Test" }
        it { expect(subject.transaction_to).to eq ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO }
      end

      context "invalid `id`" do
        let(:id) { -1 }
        it { is_expected.to be_nil }
      end
    end
  end
end
