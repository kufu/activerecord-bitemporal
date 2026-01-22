# frozen_string_literal: true

require 'spec_helper'

ActiveRecord::Schema.define(version: 1) do
  create_table :cops, force: true do |t|
    t.string :name

    t.integer :department_id

    t.integer :bitemporal_id
    t.date :valid_from
    t.date :valid_to
    t.datetime :transaction_from
    t.datetime :transaction_to

    t.timestamps
  end

  create_table :managers, force: true do |t|
    t.string :name

    t.integer :department_id

    t.integer :bitemporal_id
    t.datetime :valid_from
    t.datetime :valid_to
    t.datetime :transaction_from
    t.datetime :transaction_to

    t.timestamps
  end
end

class Cop < ActiveRecord::Base
  include ActiveRecord::Bitemporal
  belongs_to :department
end

class Manager < ActiveRecord::Base
  include ActiveRecord::Bitemporal
  belongs_to :department
end

class Department
  has_many :cops
  has_many :managers
end

RSpec.describe ActiveRecord::Bitemporal, 'date type valid time' do
  # NOTE: Use time zone other than UTC
  around { |e| Time.use_zone("Tokyo", &e) }

  describe ".create" do
    context "creating" do
      subject { Department.create!(name: "Dev") }
      it { expect { subject }.to change(Department, :count).by(1) }
    end

    context "created" do
      let(:attributes) { {} }
      subject { Department.create!(name: "Dev", **attributes) }

      context "with `bitemporal_id`" do
        let(:other_record) { Department.create!(name: "Sales", valid_from: "2019/01/01", valid_to: "2019/04/01") }
        let(:attributes) { { bitemporal_id: other_record.id, valid_from: "2019/04/01", valid_to: "2019/10/01" } }
        it {
          is_expected.to have_attributes(
            bitemporal_id: subject.id,
            previous_changes: include(
              "id" => [nil, subject.swapped_id],
              "valid_from" => [nil, "2019/04/01".to_date],
              "valid_to" => [nil, "2019/10/01".to_date],
              "name" => [nil, "Dev"]
            )
          )
        }
        it { is_expected.to have_attributes bitemporal_id: other_record.id }
      end

      context "without `bitemporal_id`" do
        it {
          is_expected.to have_attributes(
            bitemporal_id: subject.id,
            previous_changes: include(
              "id" => [nil, subject.id],
              "valid_from" => [nil, Time.zone.today],
              "valid_to" => [nil, ActiveRecord::Bitemporal::DEFAULT_VALID_TO],
              "name" => [nil, "Dev"]
            ),
            previously_force_updated?: false
          )
        }
      end
    end
  end

  describe ".find" do
    subject { Department.find(target) }

    context "exists department" do
      let!(:department) { Department.create!(name: "Test Department") }
      let(:target) { department.id }
      it { is_expected.to eq department }
    end

    context "non exists department" do
      let(:target) { nil }
      it { expect { subject }.to raise_error(ActiveRecord::RecordNotFound) }
    end

    context "with ids" do
      let!(:department1) { Timecop.travel(1.day.ago) { Department.create!(name: "Test1") } }
      let!(:department2) { Timecop.travel(1.day.ago) { Department.create!(name: "Test2") } }

      subject { Department.find(*ids) }

      before do
        department1.update(name: "Test1-2")
        department2.update(name: "Test2-2")
      end

      context "is `model.id`" do
        let(:ids) { [department1.id, department2.id, department1.id] }
        it { expect(subject.map(&:name)).to contain_exactly("Test1-2", "Test2-2") }
        it { expect(subject).to be_kind_of(Array) }
      end

      context "non exists department" do
        let(:ids) { [nil, nil, nil] }
        it { expect { subject }.to raise_error(ActiveRecord::RecordNotFound) }
      end
    end

    context "with [ids]" do
      let!(:department1) { Timecop.travel(1.day.ago) { Department.create!(name: "Test1") } }
      let!(:department2) { Timecop.travel(1.day.ago) { Department.create!(name: "Test2") } }

      subject { Department.find(ids) }

      before do
        department1.update(name: "Test1-2")
        department2.update(name: "Test2-2")
      end

      context "is `model.id`" do
        let(:ids) { [department1.id, department2.id, department1.id] }
        it { expect(subject.map(&:name)).to contain_exactly("Test1-2", "Test2-2") }
        it { expect(subject).to be_kind_of(Array) }
      end

      context "is once" do
        let(:ids) { [department1.id] }
        it { expect(subject.map(&:name)).to contain_exactly("Test1-2") }
        it { expect(subject).to be_kind_of(Array) }
      end

      context "non exists department" do
        let(:ids) { [nil, nil, nil] }
        it { expect { subject }.to raise_error(ActiveRecord::RecordNotFound) }
      end
    end
  end

  describe ".find_at_time" do
    let!(:department) { Timecop.travel(3.days.ago) { Department.create!(name: "Test1") } }
    let(:id) { department.id }
    let(:test2) { Department.ignore_valid_datetime.find_by(bitemporal_id: department.id, name: "Test2") }
    let(:test3) { Department.ignore_valid_datetime.find_by(bitemporal_id: department.id, name: "Test3") }
    let(:test4) { Department.ignore_valid_datetime.find_by(bitemporal_id: department.id, name: "Test4") }

    subject { Department.find_at_time(time, id) }

    before do
      Timecop.travel(2.days.ago) { department.update!(name: "Test2") }
      Timecop.travel(1.day.ago) { department.update!(name: "Test3") }
      department.update!(name: "Test4")
    end

    # Test2:  |-----------|
    # Test3:              |-----------|
    # Test4:                          |-----------|
    # time:   *
    context "time is `test2.valid_from`" do
      let(:time) { test2.valid_from }
      it { is_expected.to have_attributes name: "Test2" }
    end

    # Test2:  |-----------|
    # Test3:              |-----------|
    # Test4:                          |-----------|
    # time:               *
    context "time is `test2.valid_to`" do
      let(:time) { test2.valid_to }
      it { is_expected.to have_attributes name: "Test3" }
    end

    # Test2:  |-----------|
    # Test3:              |-----------|
    # Test4:                          |-----------|
    # time:               *
    context "time is `test3.valid_from`" do
      let(:time) { test3.valid_from }
      it { is_expected.to have_attributes name: "Test3" }
    end

    # Test2:  |-----------|
    # Test3:              |-----------|
    # Test4:                          |-----------|
    # time:                           *
    context "time is `test3.valid_to`" do
      let(:time) { test3.valid_to }
      it { is_expected.to have_attributes name: "Test4" }
    end

    # Test2:  |-----------|
    # Test3:              |-----------|
    # Test4:                          |-----------|
    # time:                           *
    context "time is `test4.valid_from`" do
      let(:time) { test4.valid_from }
      it { is_expected.to have_attributes name: "Test4" }
    end

    # Test2:  |-----------|
    # Test3:              |-----------|
    # Test4:                          |----------->
    # time:                                       *
    context "time is `test4.valid_to`" do
      let(:time) { test4.valid_to }
      it { is_expected.to be_nil }
    end

    # Test2:  |-----------|
    # Test3:              |-----------|
    # Test4:                          |----------->
    # time:                                 *
    context "time is now" do
      let(:time) { Time.current }
      it { is_expected.to have_attributes name: "Test4" }
    end

    # Test2:         |-----------|
    # Test3:                     |-----------|
    # Test4:                                 |----------->
    # time:     *
    context "out of time" do
      let(:time) { 10.days.ago }
      it { is_expected.to be_nil }
    end

    context "`id` is nil" do
      let(:id) { nil }
      let(:time) { Time.current }
      it { is_expected.to be_nil }
    end

    context "with ids" do
      let!(:department1) { Timecop.travel(1.day.ago) { Department.create!(name: "Test1") } }
      let!(:department2) { Timecop.travel(1.day.ago) { Department.create!(name: "Test2") } }

      subject { Department.find_at_time(datetime, *ids) }

      before do
        department1.update(name: "Test1-2")
        department2.update(name: "Test2-2")
      end

      context "is `model.id`" do
        let(:ids) { [department1.id, department2.id, department1.id] }
        context "datetime is before create time" do
          let(:datetime) { 2.days.ago }
          it { expect(subject.map(&:name)).to be_empty }
          it { expect(subject).to be_kind_of(Array) }
        end
        context "datetime is before update time" do
          let(:datetime) { 1.day.ago }
          it { expect(subject.map(&:name)).to contain_exactly("Test1", "Test2") }
          it { expect(subject).to be_kind_of(Array) }
        end
        context "datetime is after update time" do
          let(:datetime) { Time.current }
          it { expect(subject.map(&:name)).to contain_exactly("Test1-2", "Test2-2") }
          it { expect(subject).to be_kind_of(Array) }
        end
      end
    end

    context "with [ids]" do
      let!(:department1) { Timecop.travel(1.day.ago) { Department.create!(name: "Test1") } }
      let!(:department2) { Timecop.travel(1.day.ago) { Department.create!(name: "Test2") } }

      subject { Department.find_at_time(datetime, ids) }

      before do
        department1.update(name: "Test1-2")
        department2.update(name: "Test2-2")
      end

      context "is `model.id`" do
        let(:ids) { [department1.id, department2.id, department1.id] }
        context "datetime is before create time" do
          let(:datetime) { 2.days.ago }
          it { expect(subject.map(&:name)).to be_empty }
          it { expect(subject).to be_kind_of(Array) }
        end
        context "datetime is before update time" do
          let(:datetime) { 1.day.ago }
          it { expect(subject.map(&:name)).to contain_exactly("Test1", "Test2") }
          it { expect(subject).to be_kind_of(Array) }
        end
        context "datetime is after update time" do
          let(:datetime) { Time.current }
          it { expect(subject.map(&:name)).to contain_exactly("Test1-2", "Test2-2") }
          it { expect(subject).to be_kind_of(Array) }
        end
        context "is once" do
          let(:ids) { [department1.id] }
          let(:datetime) { 1.day.ago }
          it { expect(subject.map(&:name)).to contain_exactly("Test1") }
          it { expect(subject).to be_kind_of(Array) }
        end
      end
    end
  end

  describe ".valid_at" do
    let!(:department) { Timecop.travel(3.days.ago) { Department.create!(name: "Test0") } }
    let!(:update_time1) { 2.days.ago }
    let!(:update_time2) { 1.day.ago }
    let!(:update_time3) { Time.current }
    subject { Department.valid_at(time).find(department.id) }

    before do
      Timecop.travel(update_time1) { department.update!(name: "Test1") }
      Timecop.travel(update_time2) { department.update!(name: "Test2") }
      Timecop.travel(update_time3) { department.update!(name: "Test3") }
    end

    context "time is `update_time1`" do
      let(:time) { update_time1 }
      it { is_expected.to have_attributes name: "Test1" }
    end

    context "time is `update_time2`" do
      let(:time) { update_time2 }
      it { is_expected.to have_attributes name: "Test2" }
    end

    context "time is `update_time3`" do
      let(:time) { update_time3 }
      it { is_expected.to have_attributes name: "Test3" }
    end

    context "time is now" do
      let(:time) { Time.current }
      it { is_expected.to have_attributes name: "Test3" }
    end

    context "time is `nil`" do
      let(:time) { nil }
      it { is_expected.to have_attributes name: "Test3" }
    end
  end

  describe "#reload" do
    let(:department) {
      Timecop.travel(2.days.ago) { Department.create!(name: "Test1") }
        .tap { |it| Timecop.travel(1.day.ago) { it.update!(name: "Test2") } }
    }

    it { expect { department.reload }.to change { department.swapped_id_previously_was }.from(kind_of(Integer)).to(nil) }

    context "call #update" do
      subject { department.update!(name: "Test3") }
      it { expect { subject }.to change { department.reload.swapped_id } }
    end

    context "call .update" do
      subject { Department.find(department.id).update!(name: "Test3") }
      it { expect { subject }.to change { department.reload.swapped_id } }
    end

    context "within #valid_at" do
      let(:department) { Department.create!(valid_from: "2019/01/01") }
      it do
        department.valid_at("2019/04/01") { |record|
          expect(record.reload).to have_attributes(
            valid_datetime: "2019/04/01".in_time_zone,
            valid_date: "2019/04/01".to_date
          )
        }
      end
    end
  end

  describe "#update" do
    describe "updated `valid_from` and `valid_to`" do
      let(:from) { Time.zone.today }
      let(:to) { from + 10.days }
      let(:finish) { Date.new(9999, 12, 31) }
      let!(:department) { Department.create!(name: "Test", valid_from: from, valid_to: to) }
      let!(:swapped_id) { department.swapped_id }
      let(:count) { -> { Department.where(bitemporal_id: department.id).ignore_valid_datetime.count } }
      let(:old_department) { Department.ignore_bitemporal_datetime.find_by(bitemporal_id: department.id, name: "Test") }
      let(:now) { Time.current }

      subject { department.update(name: "Test2") }

      shared_examples "updated old" do
        let(:old) { Department.ignore_valid_datetime.find_by(bitemporal_id: department.id, name: "Test") }
        before { subject }
        it { expect(old).to have_attributes valid_from: valid_from, valid_to: valid_to }
      end

      shared_examples "updated current" do
        let(:current) { Department.ignore_valid_datetime.find_by(bitemporal_id: department.id, name: "Test2") }
        before { subject }
        it { expect(current).to have_attributes valid_from: valid_from, valid_to: valid_to }
      end

      around { |e| Timecop.freeze(now) { e.run } }

      # before: |-----------------------|
      # update:             *
      # after:  |-----------|
      #                     |-----------|
      context "now time is in" do
        let(:now) { from + 5.days }
        it { expect { subject }.to change(&count).by(1) }
        it { expect { subject }.to change(department, :name).from("Test").to("Test2") }
        it { expect { subject }.to change(department, :swapped_id).from(swapped_id).to(kind_of(Integer)) }
        it { expect { subject }.to change(department, :swapped_id_previously_was).from(nil).to(swapped_id) }
        it_behaves_like "updated old" do
          let(:valid_from) { from }
          let(:valid_to) { now }
        end
        it_behaves_like "updated current" do
          let(:valid_from) { now }
          let(:valid_to) { to }
        end
      end

      # before:          |-----------|     |-----------|
      # update:  *
      # after:   |-------|
      #                  |-----------|     |-----------|
      context "now time is before" do
        before do
          Department.create!(bitemporal_id: department.bitemporal_id, valid_from: to + 5.days, valid_to: to + 10.days)
        end
        let(:now) { from - 5.days }
        it { expect { subject }.to change(&count).by(1) }
        it { expect { subject }.to change(department, :name).from("Test").to("Test2") }
        it { expect { subject }.to change(department, :swapped_id).from(swapped_id).to(kind_of(Integer)) }
        it { expect { subject }.to change(department, :swapped_id_previously_was).from(nil).to(swapped_id) }
        it_behaves_like "updated old" do
          let(:valid_from) { from }
          let(:valid_to) { to }
        end
        it_behaves_like "updated current" do
          let(:valid_from) { now }
          let(:valid_to) { from }
        end
      end
    end

    describe "changed `valid_from` columns" do
      let(:department) { Timecop.travel(1.day.ago) { Department.create(name: "Test") } }
      subject { department.update(name: "Test2") }
      it { expect { subject }.to change(department, :name).from("Test").to("Test2") }
      it { expect { subject }.to change(department, :valid_from) }
      # valid_to is fixed "9999/12/31"
      it { expect { subject }.not_to change(department, :valid_to) }
    end

    context 'when updated with valid_at in the past ' do
      describe "changed `valid_to` columns" do
        let(:department) {
          ActiveRecord::Bitemporal.valid_at("2019/05/01") {
            Department.create!(name: "Test")
          }
        }
        subject {
          ActiveRecord::Bitemporal.valid_at("2019/04/01") { department.update!(name: "Test2") }
        }

        it {
          expect { subject }.to change(department, :valid_to).from(ActiveRecord::Bitemporal::DEFAULT_VALID_TO)
                                                             .to(Date.new(2019, 5, 1))
        }
      end
    end

    context "in `#valid_at`" do
      context "valid_datetime is before created time" do
        let(:department) { Timecop.freeze("2019/1/20") { Department.create!(name: "Test") } }
        let(:latest_department) { -> { Department.ignore_valid_datetime.order(:valid_from).find(department.id) } }
        subject { department.valid_at("2019/1/5", &:touch) }
        it do
          expect { subject }.to change { latest_department.call.valid_to }.from(department.valid_to).to(department.valid_from)
        end
      end
    end

    context "failure" do
      context "`valid_datetime` is `department.valid_from`" do
        let!(:department) { Department.create!(valid_from: "2019/2/1") }
        let(:department_count) { -> { Department.ignore_valid_datetime.bitemporal_for(department.id).count } }
        let(:valid_datetime) { department.valid_from }
        subject { department.valid_at(valid_datetime) { |c| c.update(name: "Department") } }

        it { expect { subject }.to raise_error(ActiveRecord::Bitemporal::ValidDatetimeRangeError) }

        context "call `update!`" do
          subject { department.valid_at(valid_datetime) { |c| c.update!(name: "Department") } }
          it { expect { subject }.to raise_error(ActiveRecord::Bitemporal::ValidDatetimeRangeError) }
          it {
            expect { subject }.to raise_error do |e|
              expect(e.message).to eq "valid_from #{department.valid_from} can't be greater than or equal to valid_to #{valid_datetime} " \
                                      "for Department with bitemporal_id=#{department.bitemporal_id}"
            end
          }
        end
      end

      context "update for deleted record" do
        let(:datetime) { "2020/01/01".in_time_zone }
        let(:department) { Department.create!(valid_from: "2019/02/01", valid_to: "2019/04/01") }
        subject { Timecop.freeze(datetime) { department.update!(name: "Department2") } }
        before { department.destroy }
        it { expect { subject }.to raise_error(ActiveRecord::RecordNotFound) }
        it {
          expect { subject }.to raise_error do |e|
            expect(e.message).to eq "Update failed: Couldn't find Department with 'bitemporal_id'=#{department.bitemporal_id} and 'valid_from' > #{datetime}"
          end
        }
      end
    end
  end

  describe "#force_update" do
    let!(:department) { Department.create!(name: "Test") }
    let!(:swapped_id) { department.swapped_id }
    let(:count) { -> { Department.ignore_valid_datetime.within_deleted.count } }
    let(:update_attributes) { { name: "Test2" } }

    subject { department.force_update { |m| m.update!(**update_attributes) } }

    it { expect { subject }.to change(&count).by(1) }
    it { expect { subject }.to change(department, :name).from("Test").to("Test2") }
    it { expect { subject }.not_to change(department, :id) }
    it { expect { subject }.to change(department, :swapped_id).from(swapped_id).to(kind_of(Integer)) }
    it { expect { subject }.to change(department, :swapped_id_previously_was).from(nil).to(swapped_id) }
    it { expect { subject }.to change(department, :previously_force_updated?).from(false).to(true) }

    context "empty `valid_datetime`" do
      it do
        department = Department.ignore_valid_datetime.find_by!(name: "Test")
        department.force_update { |m| m.update(name: "Test2") }
        expect(Department.find_at_time(department.valid_from, department.id).name).to eq "Test2"
        expect(Department.ignore_valid_datetime.where(name: "Test")).not_to be_exists
      end
    end

    context "within `valid_at`" do
      let(:uniqueness_class) do
        Class.new(Department) do
          validates :name, uniqueness: true

          def self.name
            'DepartmentWithUniquness'
          end
        end
      end

      it do
        uniqueness_class.create!(name: "Department1", valid_from: "2019/04/01", valid_to: "2019/06/01")
        department = uniqueness_class.create!(name: "Department0", valid_from: "2019/07/01")
        expect {
          ActiveRecord::Bitemporal.valid_at("2019/05/01") {
            department.force_update { |it| it.update!(name: "Department1") }
          }
        }.to_not raise_error
      end
    end

    context "update with `valid_from`" do
      let(:create_valid_from) { "2019/04/01".to_date }
      let!(:department) { Department.create!(name: "Test", valid_from: create_valid_from) }
      let(:update_valid_from) { create_valid_from + 10.days }
      let(:update_attributes) { { name: "Test2", valid_from: update_valid_from } }
      define_method(:department_all) { Department.ignore_bitemporal_datetime.bitemporal_for(department.id).order(:created_at) }

      it do
        expect { subject }.to change { department_all }
          .from(match [
            have_attributes(name: "Test", valid_from: create_valid_from, valid_to: ActiveRecord::Bitemporal::DEFAULT_VALID_TO)
          ])
          .to(match [
            have_attributes(name: "Test", valid_from: create_valid_from, valid_to: ActiveRecord::Bitemporal::DEFAULT_VALID_TO),
            have_attributes(name: "Test2", valid_from: update_valid_from, valid_to: ActiveRecord::Bitemporal::DEFAULT_VALID_TO)
          ])
      end

      context "`update_valid_from` is older than `create_valid_from`" do
        let(:update_valid_from) { create_valid_from - 10.days }

        it do
          expect { subject }.to change { department_all }
            .from(match [
              have_attributes(name: "Test", valid_from: create_valid_from, valid_to: ActiveRecord::Bitemporal::DEFAULT_VALID_TO)
            ])
            .to(match [
              have_attributes(name: "Test", valid_from: create_valid_from, valid_to: ActiveRecord::Bitemporal::DEFAULT_VALID_TO),
              have_attributes(name: "Test2", valid_from: update_valid_from, valid_to: ActiveRecord::Bitemporal::DEFAULT_VALID_TO)
            ])
        end
      end
    end
  end

  describe "#force_update?" do
    let(:department) { Department.create!(name: "Test") }
    it do
      expect(department.force_update?).to eq false
      department.force_update { expect(department.force_update?).to eq true }
      expect(department.force_update?).to eq false
    end

    context "with ActiveRecord::Bitemporal.with_bitemporal_option" do
      subject {
        ActiveRecord::Bitemporal.with_bitemporal_option(force_update: true) {
          department.force_update?
        }
      }
      it { is_expected.to be true }
    end
  end

  describe "#update_columns" do
    let!(:department) { Timecop.travel(1.day.ago) { Department.create!(name: "Test") }.tap { |m| m.update(name: "Test2") } }
    let(:original) { -> { Department.ignore_bitemporal_datetime.find_by(id: department.bitemporal_id) } }
    let(:latest) { -> { Department.find(department.id) } }
    let(:count) { -> { Department.ignore_bitemporal_datetime.count } }

    subject { department.update_columns(name: "Test3") }

    it { expect { subject }.not_to change(&count) }
    it { expect { subject }.to change { latest.call.name }.from("Test2").to("Test3") }
    it { expect { subject }.to change { department.reload.name }.from("Test2").to("Test3") }
    it { expect { subject }.not_to change { original.call.name } }
  end

  describe "#destroy" do
    let!(:department) { Timecop.freeze(created_time) { Department.create!(name: "Test") } }
    let(:represent_deleted) { Department.find_at_time(updated_time, department.id) }
    let(:time_current) { Time.current.round(6) }
    let(:created_time) { time_current - 2.day }
    let(:updated_time) { time_current - 1.day }
    let(:destroyed_time) { time_current }
    subject { Timecop.freeze(destroyed_time) { department.destroy } }

    before do
      Timecop.freeze(updated_time) { department.update!(name: "Test2") }
      @swapped_id_before_destroy = department.swapped_id
    end

    it { expect { subject }.to change(Department, :count).by(-1) }
    it { expect { subject }.to change(department, :destroyed?).from(false).to(true) }
    it { expect { subject }.not_to change(department, :valid_from) }
    it { expect { subject }.to change(department, :valid_to).from(ActiveRecord::Bitemporal::DEFAULT_VALID_TO).to(destroyed_time.to_date) }
    it { expect { subject }.to change(department, :transaction_from).from(updated_time).to(destroyed_time) }
    it { expect { subject }.not_to change(department, :transaction_to) }
    it { expect { subject }.to change { Department.ignore_bitemporal_datetime.count }.by(1) }
    it { expect { subject }.to change(department, :swapped_id).from(@swapped_id_before_destroy).to(kind_of(Integer)) }
    it { expect { subject }.to change(department, :swapped_id_previously_was).from(kind_of(Integer)).to(@swapped_id_before_destroy) }

    it do
      subject
      expect(represent_deleted).to have_attributes(
        valid_from: department.valid_from,
        valid_to: destroyed_time.to_date,
        transaction_to: ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO,
        name: department.name
      )
    end

    it "create state-destroy record before _run_destroy_callbacks" do
      before_count = Department.ignore_valid_datetime.count
      before_count_within_deleted = Department.ignore_bitemporal_datetime.count

      self_ = self
      department.define_singleton_method(:on_before_destroy) do
        self_.instance_exec { expect(Department.ignore_valid_datetime.count).to eq before_count }
        self_.instance_exec { expect(Department.ignore_bitemporal_datetime.count).to eq before_count_within_deleted }
      end

      department.define_singleton_method(:on_after_destroy) do
        self_.instance_exec { expect(Department.ignore_valid_datetime.count).to eq before_count }
        self_.instance_exec { expect(Department.ignore_bitemporal_datetime.count).to eq before_count_within_deleted + 1 }
      end

      subject
    end

    context "with callback" do
      it do
        before_time = department.valid_to
        self_ = self
        department.define_singleton_method(:on_before_destroy) {
          valid_to = self.valid_to
          # Before update valid_to
          self_.instance_exec { expect(valid_to).to eq before_time }
        }
        department.define_singleton_method(:on_after_destroy) {
          valid_to = self.valid_to
          # After update valid_to
          self_.instance_exec { expect(valid_to).to eq destroyed_time.to_date }
        }
        subject
      end
    end

    context "with `#valid_at`" do
      subject { Timecop.freeze(destroyed_time) { department.valid_at(destroyed_time + 1.day, &:destroy) } }
      it { expect { subject }.not_to change(department, :valid_from) }
      it { expect { subject }.to change(department, :valid_to).from(ActiveRecord::Bitemporal::DEFAULT_VALID_TO).to((destroyed_time + 1.day).to_date) }
      it { expect { subject }.to change(department, :transaction_from).from(updated_time).to(destroyed_time) }
      it { expect { subject }.not_to change(department, :transaction_to) }
    end

    context "with operated_at" do
      subject { department.destroy(operated_at: destroyed_time) }
      it { expect { subject }.not_to change(department, :valid_from) }
      it { expect { subject }.to change(department, :valid_to).from(ActiveRecord::Bitemporal::DEFAULT_VALID_TO).to(destroyed_time.to_date) }
      it { expect { subject }.to change(department, :transaction_from).from(updated_time).to(destroyed_time) }
      it { expect { subject }.not_to change(department, :transaction_to) }
    end

    context "with `#force_update`" do
      subject { Timecop.freeze(destroyed_time) { department.force_update { department.destroy } } }

      it { expect { subject }.to change(Department, :count).by(-1) }
      it { expect { subject }.to change(department, :destroyed?).from(false).to(true) }
      it { expect { subject }.not_to change(department, :valid_from) }
      it { expect { subject }.not_to change(department, :valid_to) }
      it { expect { subject }.not_to change(department, :transaction_from) }
      it { expect { subject }.to change(department, :transaction_to).from(ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO).to(destroyed_time) }
      it { expect { subject }.not_to change { Department.ignore_bitemporal_datetime.count } }
      it { expect { subject }.not_to change(department, :swapped_id) }
      it { expect { subject }.not_to change(department, :swapped_id_previously_was) }
      it { expect { subject }.to change(department, :previously_force_updated?).from(false).to(true) }
    end
  end

  describe "validation" do
    subject { department }
    let(:time_current) { Time.current }
    context "with `valid_from` and `valid_to`" do
      let(:department) { Department.new(name: "Test", valid_from: valid_from, valid_to: valid_to) }
      context "`valid_from` < `valid_to`" do
        let(:valid_from) { time_current }
        let(:valid_to) { valid_from + 10.days }
        it { is_expected.to be_valid }
      end

      context "`valid_from` > `valid_to`" do
        let(:valid_from) { valid_to + 10.days }
        let(:valid_to) { time_current }
        it { is_expected.to be_invalid }
      end

      context "`valid_from` == `valid_to`" do
        let(:valid_from) { time_current }
        let(:valid_to) { valid_from }
        it { is_expected.to be_invalid }
      end

      context "`valid_from` is `nil`" do
        let(:valid_from) { nil }
        let(:valid_to) { time_current }
        it { is_expected.to be_invalid }
      end

      context "`valid_to` is `nil`" do
        let(:valid_from) { time_current }
        let(:valid_to) { nil }
        it { is_expected.to be_invalid }
      end

      context "`valid_from` and `valid_to` is `nil`" do
        let(:valid_from) { nil }
        let(:valid_to) { nil }
        it { is_expected.to be_invalid }
      end
    end

    context "with `valid_from`" do
      let(:department) { Department.new(name: "Test", valid_from: valid_from) }
      let(:valid_from) { time_current }
      it { is_expected.to be_valid }
    end

    context "with `valid_to`" do
      let(:department) { Department.new(name: "Test", valid_to: valid_to) }
      let(:valid_to) { time_current + 10.days }
      it { is_expected.to be_valid }
    end

    context "blank `valid_from` and `valid_to`" do
      let(:department) { Department.new(name: "Test") }
      it { is_expected.to be_valid }
    end

    context "with `bitemporal_id`" do
      let!(:department0) { Department.create!(name: "Test") }
      subject { Department.new(name: "Test", bitemporal_id: department0.bitemporal_id).save }
      it { is_expected.to be_falsey }
    end
  end

  describe "Association" do
    describe "Date type valid time has many Date type valid time" do
      describe "sync valid_from in create" do
        let!(:cop1) { department.cops.new(name: "Jane") }
        let!(:cop2) { department.cops.new(name: "Homu") }
        let!(:cop3) { department.cops.new(name: "Mami", valid_from: "2016/01/15") }

        context "#new to #save" do
          let(:department) { Department.new(name: "Department") }

          context "saving" do
            subject { department.save }
            it { expect { subject }.to change { cop1.valid_from } }
            it { expect { subject }.to change { cop2.valid_from } }
            it { expect { subject }.not_to change { cop3.valid_from } }
          end

          context "saved" do
            subject { department.valid_from }
            before { department.save }
            it { is_expected.to eq cop1.valid_from }
            it { is_expected.to eq cop2.valid_from }
            it { expect(cop1.valid_from).to eq cop2.valid_from }
          end

          context "department with valid_from" do
            let(:department) { Department.new(name: "Department", valid_from: "2018/12/25") }
            subject { department.valid_from }
            before { department.save }

            it { is_expected.to eq "2018/12/25".to_date }
            it { is_expected.to eq cop1.valid_from }
            it { is_expected.to eq cop2.valid_from }
            it { expect(cop1.valid_from).to eq cop2.valid_from }
          end
        end

        context "#create to #save" do
          let(:department) { Timecop.travel(1.day.ago) { Department.create(name: "Department") } }

          context "saving" do
            subject { department.save }
            it { expect { subject }.to change { cop1.valid_from } }
            it { expect { subject }.to change { cop2.valid_from } }
            it { expect { subject }.not_to change { cop3.valid_from } }
          end

          context "saved" do
            before { department.save }
            subject { department.valid_from }
            it { is_expected.not_to eq cop1.valid_from }
            it { is_expected.not_to eq cop2.valid_from }
            it { expect(cop1.valid_from).to eq cop2.valid_from } # same date
          end
        end
      end

      describe "inverse_of" do
        let(:department) do
          klass = Class.new(Department) {
            has_many :cops, foreign_key: :department_id, inverse_of: :department

            def self.name
              "DepartmentWithInverseOf"
            end
          }
          Timecop.travel(1.day.ago) { klass.create!(name: "Department") }
        end
        before do
          department.update(name: "Department2")
          department.cops.create!(name: "Jane")
        end

        it { expect(department.reload.cops.first.department).to be department }
      end
    end

    describe "Date type valid time has many Datetime(timestamp) type valid time" do
      describe "sync valid_from in create" do
        let!(:manager1) { department.managers.new(name: "Jane") }
        let!(:manager2) { department.managers.new(name: "Homu") }
        let!(:manager3) { department.managers.new(name: "Mami", valid_from: "2016/01/15") }

        context "#new to #save" do
          let(:department) { Department.new(name: "Department") }

          context "saving" do
            subject { department.save }
            it { expect { subject }.to change { manager1.valid_from } }
            it { expect { subject }.to change { manager2.valid_from } }
            it { expect { subject }.not_to change { manager3.valid_from } }
          end

          context "saved" do
            subject { department.valid_from }
            before { department.save }
            it { is_expected.to eq manager1.valid_from.in_time_zone.to_date }
            it { is_expected.to eq manager2.valid_from.in_time_zone.to_date }
            it { expect(manager1.valid_from).to eq manager2.valid_from }
          end

          context "department with valid_from" do
            let(:department) { Department.new(name: "Department", valid_from: "2018/12/25") }
            subject { department.valid_from }
            before { department.save }

            it { is_expected.to eq "2018/12/25".to_date }
            it { is_expected.to eq manager1.valid_from.in_time_zone.to_date }
            it { is_expected.to eq manager2.valid_from.in_time_zone.to_date }
            it { expect(manager1.valid_from).to eq manager2.valid_from }
          end
        end

        context "#create to #save" do
          let(:department) { Timecop.travel(1.day.ago) { Department.create(name: "Department") } }

          context "saving" do
            subject { department.save }
            it { expect { subject }.to change { manager1.valid_from } }
            it { expect { subject }.to change { manager2.valid_from } }
            it { expect { subject }.not_to change { manager3.valid_from } }
          end

          context "saved" do
            before { department.save }
            subject { department.valid_from }
            it { is_expected.not_to eq manager1.valid_from }
            it { is_expected.not_to eq manager2.valid_from }
            it { expect(manager1.valid_from).not_to eq manager2.valid_from }
          end
        end
      end

      describe "inverse_of" do
        let(:department) do
          klass = Class.new(Department) {
            has_many :managers, foreign_key: :department_id, inverse_of: :department

            def self.name
              "DepartmentWithInverseOf"
            end
          }
          Timecop.travel(1.day.ago) { klass.create!(name: "Department") }
        end
        before do
          department.update(name: "Department2")
          department.managers.create!(name: "Jane")
        end

        it { expect(department.reload.managers.first.department).to be department }
      end
    end
  end

  describe "Relation" do
    describe ".all" do
      subject { Department.all }
      before do
        Timecop.travel(2.days.ago) { (1..5).each { |i| Department.create!(name: "Department#{i}") } }
        Timecop.travel(1.day.ago) do
          Department.first.update!(name: "Dev")
          Department.second.update!(name: "Dev")
          Department.third.update!(name: "Dev")
        end
        Department.third.update!(name: "Sales")
      end
      it { is_expected.to have_attributes count: 5 }
      it do
        Timecop.freeze(Time.utc(2018, 12, 25).in_time_zone) {
          expect(subject.to_sql).to match(/"departments"."valid_from" <= '2018-12-25' AND "departments"."valid_to" > '2018-12-25'/)
          expect(subject.arel.to_sql).to match(/"departments"."transaction_from" <= \$1 AND "departments"."transaction_to" > \$2/)
          expect(subject.arel.to_sql).to match(/"departments"."valid_from" <= \$3 AND "departments"."valid_to" > \$4/)
        }
      end

      context "when creating" do
        let(:count) { -> { Department.all.count } }
        subject { Department.create!(name: "Dept") }
        it { expect { subject }.to change(&count).by(1) }
      end

      context "when updating" do
        let(:count) { -> { Department.all.count } }
        subject { Department.first.update!(name: "Dept") }
        it { expect { subject }.not_to change(&count) }
      end

      context "when destroying" do
        let(:count) { -> { Department.all.count } }
        subject { Department.first.destroy! }
        it { expect { subject }.to change(&count).by(-1) }
      end
    end

    describe ".pluck" do
      subject { Department.pluck(*columns) }
      before do
        Timecop.travel(2.days.ago) { (1..5).each { |i| Department.create!(name: "Department#{i}") } }
        Timecop.travel(1.day.ago) do
          Department.first.update!(name: "Dev")
          Department.second.update!(name: "Dev")
          Department.third.update!(name: "Dev")
        end
        Department.third.update!(name: "Sales")
      end
      context "`:id` and `:bitemporal_id`" do
        let(:columns) { [:id, :bitemporal_id] }
        let(:prefix) { Department.first.id - 1 }
        it { is_expected.to contain_exactly(*[[4, 4], [5, 5], [7, 1], [9, 2], [13, 3]].map { |it| it.map(&prefix.method(:+)) }) }
      end
    end

    describe ".where" do
      subject { Department.where(name: "Dev") }
      before do
        Timecop.travel(2.days.ago) { (1..5).each { |i| Department.create!(name: "Department#{i}") } }
        Timecop.travel(1.day.ago) do
          Department.first.update!(name: "Dev")
          Department.second.update!(name: "Dev")
          Department.third.update!(name: "Dev")
        end
        Department.third.update!(name: "Sales")
      end
      it { is_expected.to have_attributes count: 2 }
      it do
        Timecop.freeze(Time.utc(2018, 12, 25).in_time_zone) {
          expect(subject.to_sql).to match(/"departments"."valid_from" <= '2018-12-25' AND "departments"."valid_to" > '2018-12-25'/)
          expect(subject.arel.to_sql).to match(/"departments"."valid_from" <= \$3 AND "departments"."valid_to" > \$4/)
        }
      end

      context "update `name` to other name" do
        before { Department.create!(name: "Dev") }
        let(:count) { -> { Department.where(name: "Dev").count } }
        subject { Department.order(:valid_from).find_by(name: "Dev").update(name: "Dev2") }
        it { expect { subject }.to change(&count).by(-1) }
      end

      context "update `name` to target name" do
        before { Department.create!(name: "Dev") }
        let(:count) { -> { Department.where(name: "Dev").count } }
        subject { Department.fourth.update!(name: "Dev") }
        it { expect { subject }.to change(&count).by(1) }
      end
    end

    describe ".count" do
      subject { Department }
      before do
        Timecop.travel(1.day.ago) { (1..3).each { |i| Department.create!(name: "Department#{i}") } }
      end
      it { is_expected.to have_attributes count: 3 }

      context "update `name`" do
        let(:count) { -> { Department.count } }
        subject { Department.first.update!(name: "Dev") }
        it { expect { subject }.not_to change(&count) }
      end

      context "force_update `valid_to`" do
        let(:count) { -> { Department.count } }
        subject { Department.first.force_update { |it| it.update!(valid_to: Time.current) } }
        it { expect { subject }.to change(&count).by(-1) }
      end
    end

    describe ".exists?" do
      context "with `valid_at" do
        before do
          Timecop.freeze("2019/1/10") { Department.create! }
        end
        subject { Department.valid_at(valid_at).exists? }
        context "`valid_at` is before create" do
          let(:valid_at) { "2019/1/5" }
          it { is_expected.to be false }
        end
        context "`valid_at` is after create" do
          let(:valid_at) { "2019/1/15" }
          it { is_expected.to be true }
        end
      end
    end

    describe ".merge" do
      let(:relation) { Department.valid_at("2019/1/1").merge(Department.valid_at("2019/2/2")) }
      subject { relation.bitemporal_option }
      it { is_expected.to include(valid_datetime: "2019/2/2".in_time_zone) }
      it { expect(relation.loaded?).to be_falsey } # `loaded?` returns nil
    end
  end
end
