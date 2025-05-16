# frozen_string_literal: true

require 'spec_helper'

ActiveRecord::Schema.define(version: 1) do
  create_table :applied_companies, force: true do |t|
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

ActiveRecord::Bitemporal.configure do |config|
  config.valid_from_key = "valid_date_from"
  config.valid_to_key = "valid_date_to"
end

class AppliedCompany < ActiveRecord::Base
  include ActiveRecord::Bitemporal
end

RSpec.describe ActiveRecord::Bitemporal, "applied valid time column name" do
  # NOTE: Use time zone other than UTC
  around { |e| Time.use_zone("Tokyo", &e) }

  describe ".create" do
    context "creating" do
      subject { AppliedCompany.create!(name: "Company") }
      it { expect { subject }.to change(AppliedCompany, :count).by(1) }
    end

    context "created" do
      let(:attributes) { {} }
      subject { AppliedCompany.create!(name: "Company", **attributes) }

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
    subject { AppliedCompany.find(target_id) }

    context "exists company" do
      let!(:company) { AppliedCompany.create!(name: "Test") }
      let(:target_id) { company.id }
      it { is_expected.to eq company }
    end

    context "non exists company" do
      let(:target_id) { nil }
      it { expect { subject }.to raise_error(ActiveRecord::RecordNotFound) }
    end
  end

  describe "#update" do
    let(:now) { Time.current }
    let(:from) { now.to_date - 1.day }
    let(:to) { now.to_date + 10.days }
    let!(:company) { AppliedCompany.create!(name: "Test1", valid_date_from: from, valid_date_to: to) }


    around { |e| Timecop.freeze(now) { e.run } }

    subject { company.update(name: "Test2") }

    it {
      subject
      actual = AppliedCompany.ignore_valid_datetime.find_by(bitemporal_id: company.id, name: "Test1")
      expect(actual).to have_attributes valid_date_from: from, valid_date_to: now.to_date
    }

    it {
      subject
      actual = AppliedCompany.ignore_valid_datetime.find_by(bitemporal_id: company.id, name: "Test2")
      expect(actual).to have_attributes valid_date_from: now.to_date, valid_date_to: to
    }
  end

  describe "#destroy" do
    let(:now) { Time.current }
    let(:created_time) { now - 3.day }
    let(:updated_time) { now - 2.day }
    let(:destroyed_time) { now - 1.day }
    let!(:company) { Timecop.freeze(created_time) { AppliedCompany.create!(name: "Test") } }
    let(:represent_deleted) { AppliedCompany.find_at_time(updated_time, company.id) }

    subject { Timecop.freeze(destroyed_time) { company.destroy } }

    before do
      Timecop.freeze(updated_time) { company.update!(name: "Test2") }
      @swapped_id_before_destroy = company.swapped_id
    end

    it { expect { subject }.to change(AppliedCompany, :count).by(-1) }
    it { expect { subject }.to change(company, :destroyed?).from(false).to(true) }
    it { expect { subject }.not_to change(company, :valid_date_from) }
    it { expect { subject }.to change(company, :valid_date_to).from(ActiveRecord::Bitemporal::DEFAULT_VALID_TO.to_date).to(destroyed_time.to_date) }
    it { expect { subject }.to change(company, :transaction_from).from(updated_time).to(destroyed_time) }
    it { expect { subject }.not_to change(company, :transaction_to) }
    it { expect { subject }.to change { AppliedCompany.ignore_bitemporal_datetime.count }.by(1) }
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
end
