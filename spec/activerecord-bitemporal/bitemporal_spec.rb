require 'spec_helper'

RSpec.describe ActiveRecord::Bitemporal do
  let(:time_current) { Time.current.round(6) }

  # Create dummy object
  before do
    (1..3).each { |i| Employee.create!(name: "Employee#{i}") }
  end

  describe ".create" do
    let(:attributes) { {} }

    context "creating" do
      subject { -> { Employee.create!(name: "Tom", **attributes) } }
      it { is_expected.to change(Employee, :call_after_save_count).by(1) }
    end

    context "created" do
      subject { Employee.create!(name: "Tom", **attributes) }

      context "with `bitemporal_id`" do
        let(:other_record) { Employee.create!(name: "Jane", valid_from: "2019/01/01", valid_to: "2019/04/01") }
        let(:attributes) { { bitemporal_id: other_record.id, valid_from: "2019/04/01", valid_to: "2019/10/01" } }
        it {
          is_expected.to have_attributes(
            bitemporal_id: subject.id,
            previous_changes: include(
              "id" => [nil, subject.swapped_id],
              "valid_from" => [nil, be_present],
              "valid_to" => [nil, "2019/10/01".in_time_zone],
              "name" => [nil, "Tom"]
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
              "valid_from" => [nil, be_present],
              "valid_to" => [nil, ActiveRecord::Bitemporal::DEFAULT_VALID_TO],
              "name" => [nil, "Tom"]
            )
          )
        }
      end

      context "blank `valid_from` and `valid_to`" do
        let(:time) { time_current }
        around { |e| Timecop.freeze(time) { e.run } }
        it { is_expected.to have_attributes(valid_from: time, valid_to:  Time.utc(9999, 12, 31).in_time_zone) }
      end
    end
  end

  describe ".find" do
    subject { Employee.find(target) }

    context "exists employee" do
      let!(:employee) { Employee.create!(name: "Test Employee") }
      let(:target) { employee.id }
      it { is_expected.to eq employee }
    end

    context "non exists employee" do
      let(:target) { nil }
      it { expect { subject }.to raise_error(ActiveRecord::RecordNotFound) }
    end

    context "with ids" do
      let!(:employee1) { Employee.create!(name: "Jane") }
      let!(:employee2) { Employee.create!(name: "Homu") }

      subject { Employee.find(*ids) }

      before do
        employee1.update(name: "Tom")
        employee2.update(name: "Mado")
      end

      context "is `model.id`" do
        let(:ids) { [employee1.id, employee2.id, employee1.id] }
        it { expect(subject.map(&:name)).to contain_exactly("Tom", "Mado") }
        it { expect(subject).to be_kind_of(Array) }
      end

      context "non exists employee" do
        let(:ids) { [nil, nil, nil] }
        it { expect { subject }.to raise_error(ActiveRecord::RecordNotFound) }
      end
    end

    context "with [ids]" do
      let!(:employee1) { Employee.create!(name: "Jane") }
      let!(:employee2) { Employee.create!(name: "Homu") }

      subject { Employee.find(ids) }

      before do
        employee1.update(name: "Tom")
        employee2.update(name: "Mado")
      end

      context "is `model.id`" do
        let(:ids) { [employee1.id, employee2.id, employee1.id] }
        it { expect(subject.map(&:name)).to contain_exactly("Tom", "Mado") }
        it { expect(subject).to be_kind_of(Array) }
      end

      context "is once" do
        let(:ids) { [employee1.id] }
        it { expect(subject.map(&:name)).to contain_exactly("Tom") }
        it { expect(subject).to be_kind_of(Array) }
      end

      context "non exists employee" do
        let(:ids) { [nil, nil, nil] }
        it { expect { subject }.to raise_error(ActiveRecord::RecordNotFound) }
      end
    end

    context "with block" do
      let!(:employee1) { Employee.create!(name: "Jane") }
      let!(:employee2) { Employee.create!(name: "Homu") }

      subject { Employee.find { |it| it.name == "Homu" } }

      before do
        @update_time = Time.current
        employee1.update(name: "Homu")
        employee2.update(name: "Jane")
      end

      it { is_expected.to eq employee1 }
      it do
        Timecop.freeze(@update_time) do
          is_expected.to eq employee2
        end
      end

      context "and ids" do
        subject { Employee.find(employee2.id) { |it| it.name == "Homu" } }
        it { is_expected.to eq employee1 }
      end
    end
  end

  describe ".find_by" do
    describe "non cache query" do
      let(:jojo) { -> { Employee.find_by(name: "JoJo") } }
      before { Employee.create(emp_code: "001", name: "JoJo") }
      subject { -> { Employee.find_by(name: "JoJo").update(emp_code: "002") } }
      it { is_expected.to change { jojo.call.emp_code }.from("001").to("002") }
    end
  end

  describe ".find_at_time" do
    let!(:employee) { Employee.create!(name: "Jone") }
    let(:id) { employee.id }
    let(:tom) { Employee.ignore_valid_datetime.find_by(bitemporal_id: employee.id, name: "Tom", deleted_at: nil) }
    let(:mami) { Employee.ignore_valid_datetime.find_by(bitemporal_id: employee.id, name: "Mami", deleted_at: nil) }
    let(:homu) { Employee.ignore_valid_datetime.find_by(bitemporal_id: employee.id, name: "Homu", deleted_at: nil) }

    subject { Employee.find_at_time(time, id) }

    before do
      employee.update!(name: "Tom")
      employee.update!(name: "Mami")
      employee.update!(name: "Homu")
    end

    # Tom:    |-----------|
    # Mami:               |-----------|
    # Homu:                           |-----------|
    # time:   *
    context "time is `tom.valid_from`" do
      let(:time) { tom.valid_from }
      it { is_expected.to have_attributes name: "Tom" }
    end

    # Tom:    |-----------|
    # Mami:               |-----------|
    # Homu:                           |----------->
    # time:               *
    context "time is `tom.valid_to`" do
      let(:time) { tom.valid_to }
      it { is_expected.to have_attributes name: "Mami" }
    end

    # Tom:    |-----------|
    # Mami:               |-----------|
    # Homu:                           |----------->
    # time:               *
    context "time is `mami.valid_from`" do
      let(:time) { mami.valid_from }
      it { is_expected.to have_attributes name: "Mami" }
    end

    # Tom:    |-----------|
    # Mami:               |-----------|
    # Homu:                           |----------->
    # time:                           *
    context "time is `mami.valid_to`" do
      let(:time) { mami.valid_to }
      it { is_expected.to have_attributes name: "Homu" }
    end

    # Tom:    |-----------|
    # Mami:               |-----------|
    # Homu:                           |----------->
    # time:                           *
    context "time is `homu.valid_from`" do
      let(:time) { homu.valid_from }
      it { is_expected.to have_attributes name: "Homu" }
    end

    # Tom:    |-----------|
    # Mami:               |-----------|
    # Homu:                           |----------->
    # time:                                       *
    context "time is `homu.valid_to`" do
      let(:time) { homu.valid_to }
      it { is_expected.to be_nil }
    end

    # Tom:    |-----------|
    # Mami:               |-----------|
    # Homu:                           |----------->
    # time:                                 *
    context "time is now" do
      let(:time) { time_current }
      it { is_expected.to have_attributes name: "Homu" }
    end

    # Tom:           |-----------|
    # Mami:                      |-----------|
    # Homu:                                  |----------->
    # time:     *
    context "out of time" do
      let(:time) { time_current - 10.days }
      it { is_expected.to be_nil }
    end

    context "`id` is nil" do
      let(:id) { nil }
      let(:time) { time_current }
      it { is_expected.to be_nil }
    end

    context "with ids" do
      let!(:start_time) { time_current }
      let!(:employee1) { Employee.create!(name: "Jane") }
      let!(:employee2) { Employee.create!(name: "Homu") }
      let!(:before_update_time) { Time.current }

      subject { Employee.find_at_time(datetime, *ids) }

      before do
        employee1.update(name: "Tom")
        employee2.update(name: "Mado")
      end

      context "is `model.id`" do
        let(:ids) { [employee1.id, employee2.id, employee1.id] }
        context "datetime is `start_time`" do
          let(:datetime) { start_time }
          it { expect(subject.map(&:name)).to be_empty }
          it { expect(subject).to be_kind_of(Array) }
        end
        context "datetime is `before_update_time`" do
          let(:datetime) { before_update_time }
          it { expect(subject.map(&:name)).to contain_exactly("Jane", "Homu") }
          it { expect(subject).to be_kind_of(Array) }
        end
        context "datetime is after_update_time" do
          let(:datetime) { Time.current }
          it { expect(subject.map(&:name)).to contain_exactly("Tom", "Mado") }
          it { expect(subject).to be_kind_of(Array) }
        end
      end
    end

    context "with [ids]" do
      let!(:start_time) { time_current }
      let!(:employee1) { Employee.create!(name: "Jane") }
      let!(:employee2) { Employee.create!(name: "Homu") }
      let!(:before_update_time) { Time.current }

      subject { Employee.find_at_time(datetime, ids) }

      before do
        employee1.update(name: "Tom")
        employee2.update(name: "Mado")
      end

      context "is `model.id`" do
        let(:ids) { [employee1.id, employee2.id, employee1.id] }
        context "datetime is `start_time`" do
          let(:datetime) { start_time }
          it { expect(subject.map(&:name)).to be_empty }
          it { expect(subject).to be_kind_of(Array) }
        end
        context "datetime is `before_update_time`" do
          let(:datetime) { before_update_time }
          it { expect(subject.map(&:name)).to contain_exactly("Jane", "Homu") }
          it { expect(subject).to be_kind_of(Array) }
        end
        context "datetime is after_update_time" do
          let(:datetime) { Time.current }
          it { expect(subject.map(&:name)).to contain_exactly("Tom", "Mado") }
          it { expect(subject).to be_kind_of(Array) }
        end
        context "is once" do
          let(:ids) { [employee1.id] }
          let(:datetime) { before_update_time }
          it { expect(subject.map(&:name)).to contain_exactly("Jane") }
          it { expect(subject).to be_kind_of(Array) }
        end
      end
    end
  end

  describe ".find_at_time!" do
    let!(:employee) { Employee.create!(name: "Jone") }
    let(:id) { employee.id }
    subject { Employee.find_at_time!(time, id) }

    context "out of time" do
      let(:id) { employee.id }
      let(:time) { time_current - 10.days }
      it { expect { subject }.to raise_error(ActiveRecord::RecordNotFound) }
    end

    context "`id` is nil" do
      let(:id) { nil }
      let(:time) { time_current }
      it { expect { subject }.to raise_error(ActiveRecord::RecordNotFound) }
    end

    context "with ids" do
      let!(:start_time) { time_current }
      let!(:employee1) { Employee.create!(name: "Jane") }
      let!(:employee2) { Employee.create!(name: "Homu") }
      let!(:before_update_time) { Time.current }

      subject { Employee.find_at_time!(datetime, *ids) }

      before do
        employee1.update(name: "Tom")
        employee2.update(name: "Mado")
      end

      context "is `model.id`" do
        let(:ids) { [employee1.id, employee2.id, employee1.id] }
        context "datetime is `start_time`" do
          let(:datetime) { start_time }
          it { expect { subject }.to raise_error(ActiveRecord::RecordNotFound) }
        end
        context "datetime is `before_update_time`" do
          let(:datetime) { before_update_time }
          it { expect(subject.map(&:name)).to contain_exactly("Jane", "Homu") }
          it { expect(subject).to be_kind_of(Array) }
        end
        context "datetime is after_update_time" do
          let(:datetime) { Time.current }
          it { expect(subject.map(&:name)).to contain_exactly("Tom", "Mado") }
          it { expect(subject).to be_kind_of(Array) }
        end
      end
    end

    context "with [ids]" do
      let!(:start_time) { time_current }
      let!(:employee1) { Employee.create!(name: "Jane") }
      let!(:employee2) { Employee.create!(name: "Homu") }
      let!(:before_update_time) { Time.current }

      subject { Employee.find_at_time!(datetime, ids) }

      before do
        employee1.update(name: "Tom")
        employee2.update(name: "Mado")
      end

      context "is `model.id`" do
        let(:ids) { [employee1.id, employee2.id, employee1.id] }
        context "datetime is `start_time`" do
          let(:datetime) { start_time }
          it { expect { subject }.to raise_error(ActiveRecord::RecordNotFound) }
        end
        context "datetime is `before_update_time`" do
          let(:datetime) { before_update_time }
          it { expect(subject.map(&:name)).to contain_exactly("Jane", "Homu") }
          it { expect(subject).to be_kind_of(Array) }
        end
        context "datetime is after_update_time" do
          let(:datetime) { Time.current }
          it { expect(subject.map(&:name)).to contain_exactly("Tom", "Mado") }
          it { expect(subject).to be_kind_of(Array) }
        end
        context "is once" do
          let(:ids) { [employee1.id] }
          let(:datetime) { before_update_time }
          it { expect(subject.map(&:name)).to contain_exactly("Jane") }
          it { expect(subject).to be_kind_of(Array) }
        end
      end
    end
  end

  describe ".valid_at" do
    let!(:employee) { Employee.create!(name: "Jone") }
    let!(:update_time1) { employee.update(name: "Tom"); Time.current }
    let!(:update_time2) { employee.update(name: "Mami"); Time.current }
    let!(:update_time3) { employee.update(name: "Homu"); Time.current }
    subject { Employee.valid_at(time).find(employee.id) }

    context "time is `update_time1`" do
      let(:time) { update_time1 }
      it { is_expected.to have_attributes name: "Tom" }
    end

    context "time is `update_time2`" do
      let(:time) { update_time2 }
      it { is_expected.to have_attributes name: "Mami" }
    end

    context "time is `update_time3`" do
      let(:time) { update_time3 }
      it { is_expected.to have_attributes name: "Homu" }
    end

    context "time is now" do
      let(:time) { time_current }
      it { is_expected.to have_attributes name: "Homu" }
    end

    context "time is `nil`" do
      let(:time) { nil }
      it { is_expected.to have_attributes name: "Homu" }
    end

    context "with time zone" do
      let!(:old_time_zone) { Time.zone }
      subject { Employee.valid_at(valid_datetime).find_by(bitemporal_id: @employee.bitemporal_id) }

      before do
        Time.zone = "Tokyo"
        Timecop.freeze("2018/12/5 10:00"){
          @employee = Employee.create(name: "Akane")
        }
      end
      after { Time.zone = old_time_zone }

      it do
        Employee.valid_at("2018/12/5 9:00").tap { |m|
          expect(m.valid_datetime.zone).to eq "+09:00"
        }
      end

      context "before created time" do
        let(:valid_datetime) { "2018/12/5 9:00" }
        it { is_expected.to be_nil }
      end
      context "after created time" do
        let(:valid_datetime) { "2018/12/5 11:00" }
        it { is_expected.not_to be_nil }
      end
    end

    context "without block" do
      it { expect(Employee.valid_at(update_time1).find(employee.id)).to have_attributes name: "Tom" }
      it { expect(Employee.valid_at(update_time2).find(employee.id)).to have_attributes name: "Mami" }
      it { expect(Employee.valid_at(update_time3).find(employee.id)).to have_attributes name: "Homu" }
    end
  end

  describe ".bitemporal_id_key" do
    context "not defined `.bitemporal_id_key`" do
      subject { Employee }
      it { expect(subject).to have_attributes bitemporal_id_key: "bitemporal_id" }
      it { expect(subject.new).to have_attributes bitemporal_id_key: "bitemporal_id" }
    end
    context "defined `.bitemporal_id_key`" do
      let(:with_bitemporal_id_key_class) {
        Class.new(Employee) {
          def self.bitemporal_id_key
            "original_id"
          end
        }
      }
      subject { with_bitemporal_id_key_class }
      it { expect(subject).to have_attributes bitemporal_id_key: "original_id" }
      it { expect(subject.new).to have_attributes bitemporal_id_key: "original_id" }
    end
  end

  describe ".bitemporalize" do
    let(:option) { {} }
    let(:model_class) {
      opt = option
      Class.new(ActiveRecord::Base) {
        bitemporalize(**opt)
      }
    }
    describe "with `enable_strict_by_validates_bitemporal_id`" do
      subject { model_class.validators_on(:bitemporal_id).first.options[:strict] }
      context "empty" do
        let(:option) { {} }
        it { is_expected.to be_falsey }
      end
      context "`true`" do
        let(:option) { { enable_strict_by_validates_bitemporal_id: true } }
        it { is_expected.to be_truthy }
      end
      context "`false`" do
        let(:option) { { enable_strict_by_validates_bitemporal_id: false } }
        it { is_expected.to be_falsey }
      end
    end

    describe 'attributes' do
      before do
        model_class.table_name = 'families'
      end

      it 'truncates time on assignment' do
        time = Time.new(2000, 1, 1, 0, 0, 0).change(nsec: 12345)

        instance = model_class.new(
          valid_from: time,
          valid_to: time
        )

        expect(instance.valid_from.nsec).to eq(0)
        expect(instance.valid_to.nsec).to eq(0)
      end
    end
  end

  describe "#reload" do
    let(:employee) { Employee.create!(name: "Tom").tap { |emp| emp.update!(name: "Jane") } }

    context "call #update" do
      subject { -> { employee.update!(name: "Kevin") } }
      it { is_expected.to change { employee.reload.swapped_id } }
    end

    context "call .update" do
      subject { -> { Employee.find(employee.id).update!(name: "Kevin") } }
      it { is_expected.to change { employee.reload.swapped_id } }
    end
  end

  describe "#ignore_valid_datetime" do
    let!(:employee) { Employee.create!(name: "Jone") }
    let(:update) { -> { Employee.find(employee.id).update(name: "Tom"); Time.current } }

    context "called by `ActiveRecord_Relation`" do
      let(:count) { -> { Employee.where(bitemporal_id: employee).ignore_valid_datetime.count } }
      it { expect(&update).to change(&count).by(1) }
    end

    context "called by `ActiveRecord::Base Model`" do
      let(:count) { -> { Employee.ignore_valid_datetime.where(bitemporal_id: employee).count } }
      it { expect(&update).to change(&count).by(1) }
    end

    context "without block" do
      let(:count) { -> { Employee.ignore_valid_datetime.where(bitemporal_id: employee).count } }
      it { expect(&update).to change(&count).by(1) }
    end
  end

  describe "#update" do
    describe "updated `valid_from` and `valid_to`" do
      let(:from) { time_current }
      let(:to) { from + 10.days }
      let(:finish) { Time.utc(9999, 12, 31).in_time_zone }
      let!(:employee) { Employee.create!(name: "Jone", valid_from: from, valid_to: to) }
      let(:count) { -> { Employee.where(bitemporal_id: employee.id).ignore_valid_datetime.count } }
      let(:old_jone) { Employee.ignore_valid_datetime.where.not(deleted_at: nil).find_by(bitemporal_id: employee.id, name: "Jone") }
      let(:now) { time_current }

      subject { -> { employee.update(name: "Tom") } }

      shared_examples "updated Jone" do
        let(:jone) { Employee.ignore_valid_datetime.find_by(bitemporal_id: employee.id, name: "Jone", deleted_at: nil) }
        before { subject.call }
        it { expect(jone).to have_attributes valid_from: valid_from, valid_to: valid_to }
      end

      shared_examples "updated Tom" do
        let(:tom) { Employee.ignore_valid_datetime.find_by(bitemporal_id: employee.id, name: "Tom", deleted_at: nil) }
        before { subject.call }
        it { expect(tom).to have_attributes valid_from: valid_from, valid_to: valid_to }
      end

      around { |e| Timecop.freeze(now) { e.run } }

      # before: |-----------------------|
      # update:             *
      # after:  |-----------|
      #                     |-----------|
      context "now time is in" do
        let(:now) { from + 5.days }
        it { is_expected.to change(&count).by(1) }
        it { is_expected.to change(employee, :name).from("Jone").to("Tom") }
        it { is_expected.to change(employee, :swapped_id) }
        it_behaves_like "updated Jone" do
          let(:valid_from) { from }
          let(:valid_to) { now }
        end
        it_behaves_like "updated Tom" do
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
          Employee.create!(bitemporal_id: employee.bitemporal_id, valid_from: to + 5.days, valid_to: to + 10.days)
        end
        let(:now) { from - 5.days }
        it { is_expected.to change(&count).by(1) }
        it { is_expected.to change(employee, :name).from("Jone").to("Tom") }
        it { is_expected.to change(employee, :swapped_id) }
        it_behaves_like "updated Jone" do
          let(:valid_from) { from }
          let(:valid_to) { to }
        end
        it_behaves_like "updated Tom" do
          let(:valid_from) { now }
          let(:valid_to) { from }
        end
      end

      # TODO
      # before |-----------|
      #                        *
      # after  |-----------|
      #                        |----------->
      xcontext "now time is after" do
        let(:now) { to + 5.days }
        it_behaves_like "updated Jone" do
          let(:valid_from) { from }
          let(:valid_to) { to }
        end
        it_behaves_like "updated Tom" do
          let(:valid_from) { now }
          let(:valid_to) { finish }
        end
      end
    end

    context "wrapper method with the same name as the column name" do
      let!(:employee) { Employee.create(name: "Jone") }
      # Update to { name: employee.name } # => "wrapped #{self[:name]}"
      subject { employee.update(name: "Tom") }

      before do
        def employee.name
            wrapped_name
            "wrapped #{self[:name]}"
        end

        def employee.wrapped_name
        end

        allow(employee).to receive(:wrapped_name)
        allow_any_instance_of(Employee).to receive(:name=).and_call_original
      end

      it { expect { subject }.to change(employee, :name).from("wrapped Jone").to("wrapped Tom") }

      it do
        subject
        expect(employee).to have_received(:wrapped_name).once
        expect(employee).to have_received(:name=).once
      end
    end

    context "defined #bitemporal_ignore_update_columns" do
      let!(:employee) { Employee.create(emp_code: "001", name: "Jane") }
      let(:ignore_columns) { [] }
      let(:histories) { -> { Employee.ignore_valid_datetime.where(bitemporal_id: employee.bitemporal_id, deleted_at: nil).order(valid_from: :desc) } }
      let(:now) { -> { histories.call.first } }
      let(:old) { -> { histories.call.second } }

      subject { -> { employee.update(emp_code: "002", name: "Tom") } }

      before do
        ignore_columns_ = ignore_columns
        employee.define_singleton_method(:bitemporal_ignore_update_columns) do
          ignore_columns_
        end
      end

      context "return to Symbol" do
        let(:ignore_columns) { [:name] }

        # It did not work.
        # it { is_expected.to change(&now).from(have_attributes(emp_code: "001", name: "Jane")).to(have_attributes(emp_code: "002", name: nil)) }
        it { is_expected.to change { now.call.name }.from("Jane").to(nil) }
        it { is_expected.to change { now.call.emp_code }.from("001").to("002") }
        it { is_expected.to change(&old).from(nil).to(have_attributes(emp_code: "001", name: "Jane")) }
      end

      context "return to String" do
        let(:ignore_columns) { ["name"] }

        it { is_expected.to change { now.call.name }.from("Jane").to(nil) }
        it { is_expected.to change { now.call.emp_code }.from("001").to("002") }
        it { is_expected.to change(&old).from(nil).to(have_attributes(emp_code: "001", name: "Jane")) }
      end
    end

    describe "changed `valid_from` columns" do
      let(:employee) { Employee.create(name: "Jane", emp_code: "001") }
      subject { -> { employee.update(name: "Tom") } }
      it { is_expected.to change(employee, :name).from("Jane").to("Tom") }
      it { is_expected.to change(employee, :valid_from) }
      # valid_to is fixed "9999/12/31"
      it { is_expected.not_to change(employee, :valid_to) }
      it { is_expected.not_to change(employee, :emp_code) }
    end

    context "in `#valid_at`" do
      describe "set deleted_at" do
        let(:employee) { Timecop.freeze("2019/1/1") { Employee.create!(name: "Jane") } }
        let(:time_current) { employee.updated_at + 10.days }
        let(:valid_at) { employee.updated_at + 5.days }
        let(:employee_deleted_at) {
          Employee.ignore_valid_datetime.within_deleted.where.not(deleted_at: nil).find(employee.id).deleted_at
        }
        subject { employee_deleted_at }
        before do
          Timecop.freeze(time_current) { employee.valid_at(valid_at) { |m| m.update!(name: "Tom") } }
        end
        it { is_expected.to eq time_current }
      end

      context "valid_datetime is before created time" do
        let(:employee) { Timecop.freeze("2019/1/20") { Employee.create!(name: "Jane") } }
        let(:latest_employee) { -> { Employee.ignore_valid_datetime.order(:valid_from).find(employee.id) } }
        subject { -> { employee.valid_at("2019/1/5", &:touch) } }
        before { Timecop.freeze("2019/1/10") { Employee.create!(name: "Homu") } }
        it do
          is_expected.to change { latest_employee.call.valid_to }.from(employee.valid_to).to(employee.valid_from)
        end
      end
    end

    context "failure" do
      let(:company) { Company.create!(valid_from: "2019/2/1") }
      let(:company_count) { -> { Company.ignore_valid_datetime.bitemporal_for(company.id).count } }
      let(:company_deleted_at) { -> { Company.ignore_valid_datetime.within_deleted.bitemporal_for(company.id).first.deleted_at } }
      subject { -> { company.valid_at(valid_datetime) { |c| c.update(name: "Company") } } }

      context "`valid_datetime` is `company.valid_from`" do
        let(:valid_datetime) { company.valid_from }

        it { expect(subject.call).to be_falsey }
        it { is_expected.not_to change(&company_count) }
        it { is_expected.not_to change(&company_deleted_at) }

        context "call `update!`" do
          subject { -> { company.valid_at(valid_datetime) { |c| c.update!(name: "Company") } } }
          it { is_expected.to raise_error(ActiveRecord::RecordNotSaved) }
        end
      end
    end
  end

  describe "#force_update" do
    let!(:employee) { Employee.create!(name: "Jane") }
    let(:count) { -> { Employee.ignore_valid_datetime.within_deleted.count } }
    let(:update_attributes) { { name: "Tom" } }

    subject { -> { employee.force_update { |m| m.update!(**update_attributes) } } }

    it { is_expected.to change(&count).by(1) }
    it { is_expected.to change(employee, :name).from("Jane").to("Tom") }
    it { is_expected.not_to change(employee, :id) }
    it { is_expected.to change(employee, :swapped_id) }

    context "with `#valid_at`" do
      let!(:employee) { Timecop.freeze("2019/1/1") { Employee.create!(name: "Jane") } }
      let(:time_current) { employee.updated_at + 10.days }
      let(:valid_at) { employee.updated_at + 5.days }
      let(:employee_deleted_at) {
        Employee.ignore_valid_datetime.within_deleted.where.not(deleted_at: nil).find(employee.id).deleted_at
      }
      subject { employee_deleted_at }
      before do
        Timecop.freeze(time_current) { employee.valid_at(valid_at) { |m| m.update!(name: "Tom") } }
      end
      it { is_expected.to eq time_current }
    end

    context "empty `valid_datetime`" do
      it do
        employee = Employee.ignore_valid_datetime.where(name: "Jane", deleted_at: nil).first
        employee.force_update { |m| m.update(name: "Kevin") }
        expect(Employee.find_at_time(employee.valid_from, employee.id).name).to eq "Kevin"
        expect(Employee.ignore_valid_datetime.where(name: "Jane", deleted_at: nil).exists?).to be_falsey
      end
    end

    context "within `valid_at`" do
      class EmployeeWithUniquness < Employee
        validates :name, uniqueness: true
      end

      it do
        EmployeeWithUniquness.create!(name: "Company1", valid_from: "2019/04/01", valid_to: "2019/06/01")
        company = EmployeeWithUniquness.create!(name: "Company0", valid_from: "2019/07/01")
        expect {
          ActiveRecord::Bitemporal.valid_at("2019/05/01") {
            company.force_update { |it| it.update!(name: "Company1") }
          }
        }.to_not raise_error
      end
    end

    context "update with `valid_from`" do
      let(:create_valid_from) { "2019/04/01".to_time }
      let!(:employee) { Employee.create!(name: "Jane", valid_from: create_valid_from) }
      let(:update_valid_from) { create_valid_from + 10.days }
      let(:update_attributes) { { name: "Tom", valid_from: update_valid_from } }
      define_method(:employee_all) { Employee.ignore_valid_datetime.within_deleted.bitemporal_for(employee.id).order(:created_at) }

      it do
        is_expected.to change { employee_all }
          .from(match [
            have_attributes(name: "Jane", valid_from: create_valid_from, valid_to: ActiveRecord::Bitemporal::DEFAULT_VALID_TO, deleted_at: be_blank)
          ])
          .to(match [
            have_attributes(name: "Jane", valid_from: create_valid_from, valid_to: ActiveRecord::Bitemporal::DEFAULT_VALID_TO, deleted_at: be_present),
            have_attributes(name: "Tom", valid_from: update_valid_from, valid_to: ActiveRecord::Bitemporal::DEFAULT_VALID_TO, deleted_at: be_blank)
          ])
      end

      context "`update_valid_from` is older than `create_valid_from`" do
        let(:update_valid_from) { create_valid_from - 10.days }

        it do
          is_expected.to change { employee_all }
            .from(match [
              have_attributes(name: "Jane", valid_from: create_valid_from, valid_to: ActiveRecord::Bitemporal::DEFAULT_VALID_TO, deleted_at: be_blank)
            ])
            .to(match [
              have_attributes(name: "Jane", valid_from: create_valid_from, valid_to: ActiveRecord::Bitemporal::DEFAULT_VALID_TO, deleted_at: be_present),
              have_attributes(name: "Tom", valid_from: update_valid_from, valid_to: ActiveRecord::Bitemporal::DEFAULT_VALID_TO, deleted_at: be_blank)
            ])
        end
      end
    end
  end

  describe "#force_update?" do
    let(:employee) { Employee.create!(name: "Jone") }
    it do
      expect(employee.force_update?).to eq false
      employee.force_update { expect(employee.force_update?).to eq true }
      expect(employee.force_update?).to eq false
    end

    context "with ActiveRecord::Bitemporal.with_bitemporal_option" do
      subject {
        ActiveRecord::Bitemporal.with_bitemporal_option(force_update: true) {
          Employee.first.force_update?
        }
      }
      it { is_expected.to be_truthy }
    end
  end

  describe "#update_columns" do
    let!(:employee) { Employee.create!(name: "Jane").tap { |m| m.update(name: "Tom") } }
    let(:original) { -> { Employee.ignore_valid_datetime.within_deleted.find_by(id: employee.bitemporal_id) } }
    let(:latest) { -> { Employee.find(employee.id) } }
    let(:count) { -> { Employee.ignore_valid_datetime.within_deleted.count } }

    subject { -> { employee.update_columns(name: "Homu") } }

    it { is_expected.not_to change(&count) }
    it { is_expected.to change { latest.call.name }.from("Tom").to("Homu") }
    it { is_expected.to change { employee.reload.name }.from("Tom").to("Homu") }
    it { is_expected.not_to change { original.call.name} }
  end

  describe "#destroy" do
    let!(:employee) { Timecop.freeze(created_time) { Employee.create!(name: "Jone") } }
    let(:represent_deleted) { Employee.find_at_time(updated_time, employee.id) }
    let(:created_time) { time_current - 10.second }
    let(:updated_time) { time_current - 5.second }
    let(:destroyed_time) { time_current }
    subject { -> { Timecop.freeze(destroyed_time) { employee.destroy } } }

    before do
      Timecop.freeze(updated_time) { employee.update!(name: "Tom") }
    end

    it { is_expected.not_to change(employee, :valid_to) }
    it { is_expected.to change(Employee, :call_before_destroy_count).by(1) }
    it { is_expected.to change(Employee, :call_after_destroy_count).by(1) }
    it { is_expected.to change(Employee, :call_after_save_count) }
    it { is_expected.to change(Employee, :count).by(-1) }
    it { is_expected.to change(employee, :destroyed?).from(false).to(true) }
    it { is_expected.not_to change(employee, :valid_from) }
    it { is_expected.not_to change(employee, :valid_to) }
    it { is_expected.to change(employee, :deleted_at).from(nil).to(destroyed_time) }
    it { is_expected.to change { Employee.ignore_valid_datetime.within_deleted.count }.by(1) }
    it { expect(subject.call).to eq employee }

    it do
      subject.call
      expect(represent_deleted).to have_attributes(
        valid_from: employee.valid_from,
        valid_to: destroyed_time,
        deleted_at: nil,
        name: employee.name,
        emp_code: employee.emp_code
      )
    end

    it "create state-destroy record before _run_destroy_callbacks" do
      before_count = Employee.ignore_valid_datetime.count
      before_count_within_deleted = Employee.ignore_valid_datetime.within_deleted.count

      self_ = self
      employee.define_singleton_method(:on_before_destroy) do
        self_.instance_exec { expect(Employee.ignore_valid_datetime.count).to eq before_count }
        self_.instance_exec { expect(Employee.ignore_valid_datetime.within_deleted.count).to eq before_count_within_deleted }
      rescue => e
        self_.instance_exec { expect(e).to eq true }
      end

      employee.define_singleton_method(:on_after_destroy) do
        self_.instance_exec { expect(Employee.ignore_valid_datetime.count).to eq before_count }
        self_.instance_exec { expect(Employee.ignore_valid_datetime.within_deleted.count).to eq before_count_within_deleted + 1 }
      rescue => e
        self_.instance_exec { expect(e).to eq true }
      end

      subject.call
    end

    context "when raise exception" do
      shared_examples "return false and #destroyed? to be false" do
        it { is_expected.not_to change(employee, :destroyed?) }
        it { is_expected.not_to change { Employee.ignore_valid_datetime.count } }
        it { expect(subject.call).to eq false }
        it do
          subject.call
          expect(employee.reload.deleted_at).to be_nil
        end
      end

      context "at #update_columns" do
        before { allow(employee).to receive(:update_columns).and_raise(ActiveRecord::ActiveRecordError) }

        it_behaves_like "return false and #destroyed? to be false"
      end

      context "at #save!" do
        before { allow_any_instance_of(Employee).to receive('save!').and_raise(ActiveRecord::RecordNotSaved) }

        it_behaves_like "return false and #destroyed? to be false"
      end

      context "at `before_destroy`" do
        context "with raise" do
          let(:employee) {
            Class.new(Employee) {
              before_destroy { raise Error }
            }.create(name: "Jane")
          }

          it_behaves_like "return false and #destroyed? to be false"
        end

        context "with throw(:abort)" do
          let(:employee) {
            Class.new(Employee) {
              before_destroy { throw :abort }
            }.create(name: "Jane")
          }

          it_behaves_like "return false and #destroyed? to be false"
        end
      end
    end

    context "with callback" do
      it do
        before_time = employee.valid_to
        self_ = self
        employee.define_singleton_method(:on_before_destroy){
          valid_to = self.valid_to
          # Before update valid_to
          self_.instance_exec { expect(valid_to).to eq before_time }
        }
        employee.define_singleton_method(:on_after_destroy){
          valid_to = self.valid_to
          # After update valid_to
          self_.instance_exec { expect(valid_to).to eq before_time }
        }
        subject.call
      end
    end

    context "after changing" do
      let(:deleted_histroy_record) { Employee.ignore_valid_datetime.where(bitemporal_id: employee.bitemporal_id, deleted_at: nil).order(:created_at).to_a.last }
      before do
        employee.name = "Homu"
        employee.destroy
      end
      it { expect(deleted_histroy_record).to have_attributes name: "Tom" }
    end

    context "with `#valid_at`" do
      subject { -> { Timecop.freeze(destroyed_time) { employee.valid_at(destroyed_time + 1.days, &:destroy) } } }
      it { is_expected.to change(employee, :deleted_at).from(nil).to(destroyed_time) }
    end
  end

  describe "#touch" do
    let!(:employee) { Employee.create(name: "Jane").tap { |it| it.update!(name: "Tom") } }
    let(:employee_count) { -> { Employee.ignore_valid_datetime.bitemporal_for(employee.id).count } }
    subject { -> { employee.touch(:archived_at) } }

    it { expect(employee).to have_attributes(name: "Tom", id: employee.id) }
    it { expect(subject.call).to eq true }
    it { is_expected.to change(&employee_count).by(1) }
    it { is_expected.to change { employee.reload.archived_at }.from(nil) }
  end

  describe "validation" do
    subject { employee }
    context "with `valid_from` and `valid_to`" do
      let(:employee) { Employee.new(name: "Jane", valid_from: valid_from, valid_to: valid_to) }
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
      let(:employee) { Employee.new(name: "Jane", valid_from: valid_from) }
      let(:valid_from) { time_current }
      it { is_expected.to be_valid }
    end

    context "with `valid_to`" do
      let(:employee) { Employee.new(name: "Jane", valid_to: valid_to) }
      let(:valid_to) { time_current + 10.days }
      it { is_expected.to be_valid }
    end

    context "blank `valid_from` and `valid_to`" do
      let(:employee) { Employee.new(name: "Jane") }
      it { is_expected.to be_valid }
    end

    context "with `bitemporal_id`" do
      let!(:employee0) { Employee.create!(name: "Jane") }
      subject { Employee.new(name: "Jane", bitemporal_id: employee0.bitemporal_id).save }
      it { is_expected.to be_falsey }
    end
  end

  describe "transaction" do
    context "with raise" do
      let!(:employee) { Employee.create(name: "Jane") }
      subject {
        -> {
          ActiveRecord::Base.transaction do
            employee.update(name: "Tom")
            raise ActiveRecord::Rollback
          end
        }
      }
      it { is_expected.not_to change { employee.reload.name } }
      it { is_expected.not_to change { Employee.ignore_valid_datetime.count } }
    end
  end

  describe "Optionable" do
    describe "#bitemporal_option" do
      context "after query method" do
        let(:previous_year) { 1.year.ago.beginning_of_year.to_date }
        let(:current_year) { Time.current.beginning_of_year.to_date }
        let(:next_year) { 1.year.since.beginning_of_year.to_date }
        let!(:employee) { Employee.create(emp_code: "001", name: "Tom", valid_from: previous_year, valid_to: next_year) }
        context "not `valid_at`" do
          it { expect(Employee.find(employee.id).bitemporal_option).to be_empty }
          it { expect(Employee.find_by(name: "Tom").bitemporal_option).to be_empty }
          it { expect(Employee.where(name: "Tom").first.bitemporal_option).to be_empty }
        end

        context "`valid_at` within call bitemporal_option" do
          it { expect(Employee.valid_at(current_year).find(employee.id).bitemporal_option).to eq(valid_datetime: current_year) }
          it { expect(Employee.valid_at(current_year).find_by(name: "Tom").bitemporal_option).to eq(valid_datetime: current_year) }
          it { expect(Employee.valid_at(current_year).where(name: "Tom").first.bitemporal_option).to eq(valid_datetime: current_year) }
        end

        context "`valid_at` without call bitemporal_option" do
          it { expect(Employee.valid_at(current_year).find(employee.id).bitemporal_option).to eq(valid_datetime: current_year) }
          it { expect(Employee.valid_at(current_year).find_by(name: "Tom").bitemporal_option).to eq(valid_datetime: current_year) }
          it { expect(Employee.valid_at(current_year).where(name: "Tom").first.bitemporal_option).to eq(valid_datetime: current_year) }
        end

        context "relation to `valid_at`" do
          it { expect(Employee.where(emp_code: "001").valid_at(current_year).find(employee.id).bitemporal_option).to eq(valid_datetime: current_year) }
          it { expect(Employee.where(emp_code: "001").valid_at(current_year).find_by(name: "Tom").bitemporal_option).to eq(valid_datetime: current_year) }
          it { expect(Employee.where(emp_code: "001").valid_at(current_year).where(name: "Tom").first.bitemporal_option).to eq(valid_datetime: current_year) }
        end
      end

      context "call with_bitemporal_option" do
        subject { -> { ActiveRecord::Bitemporal.with_bitemporal_option(valid_datetime: "2010/4/1"){} } }
        it { is_expected.not_to change(ActiveRecord::Bitemporal, :bitemporal_option) }
        it { is_expected.not_to change { Employee.all.bitemporal_option } }
      end

      context "nested with_bitemporal_option" do
        let!(:employee) { Employee.create(name: "Jane", valid_from: "2019/1/1", valid_to: "2019/1/10") }
        it do
          opt1 = { valid_datetime: "2010/4/1", ignore_valid_datetime: false }
          ActiveRecord::Bitemporal.with_bitemporal_option(**opt1) {
            expect(ActiveRecord::Bitemporal.bitemporal_option).to eq(opt1)
            expect(Employee.all.bitemporal_option).to eq(opt1)

            opt2 = { ignore_valid_datetime: true }
            ActiveRecord::Bitemporal.with_bitemporal_option(**opt2) {
              expect(ActiveRecord::Bitemporal.bitemporal_option).to eq(opt1.merge(opt2))
              expect(Employee.all.bitemporal_option).to eq(opt1.merge(opt2))

              opt3 = { valid_datetime: "2019/1/5" }
              Employee.with_bitemporal_option(**opt3) { |m|
                expect(m.find(employee.id).name).to eq "Jane"
                expect(m.find(employee.id).valid_datetime).to eq "2019/1/5".in_time_zone.to_datetime
                expect(Employee.find_at_time("2019/1/5", employee.id).name).to eq "Jane"
                expect(ActiveRecord::Bitemporal.bitemporal_option).to eq(opt1.merge(opt2))
                expect(m.bitemporal_option).to eq(opt1.merge(opt2).merge(opt3))
              }
              expect(Employee.find_at_time("2019/1/5", employee.id).name).to eq "Jane"
              expect(ActiveRecord::Bitemporal.bitemporal_option).to eq(opt1.merge(opt2))
              expect(Employee.all.bitemporal_option).to eq(opt1.merge(opt2))
            }
            employee.update(name: "Tom")
            expect(ActiveRecord::Bitemporal.bitemporal_option).to eq(opt1)
            expect(Employee.all.bitemporal_option).to eq(opt1)
          }
          expect(ActiveRecord::Bitemporal.bitemporal_option).to be_empty
          expect(Employee.all.bitemporal_option).to be_empty
        end
      end
    end

    describe "ActiveRecord::Bitemporal.valid_at" do
      context "instance object" do
        let!(:company) { Company.create(name: "Company") }
        before do
          emp = company.employees.create(name: "Jane")
          emp.address = Address.create(name: "Address")
        end
        it do
          Company.includes(:employees, employees: :address).find_at_time(time_current, company.id).tap { |c|
            expect(c.valid_datetime).to eq time_current
            expect(c.employees.first.valid_datetime).to eq time_current
            expect(c.employees.first.address.valid_datetime).to eq time_current
            ActiveRecord::Bitemporal.valid_at("2019/1/1") {
              expect(c.valid_datetime).to eq time_current
              expect(c.employees.first.valid_datetime).to eq time_current
              expect(c.employees.first.address.valid_datetime).to eq time_current
            }
          }
        end

        context "with ignore_valid_datetime" do
          it do
            result = ActiveRecord::Bitemporal.valid_at("2019/1/1") {
              expect(Employee.ignore_valid_datetime.to_sql).not_to match %r/"valid_from" <= /
              expect(Employee.ignore_valid_datetime.to_sql).not_to match %r/"valid_to" > /
              expect(Employee.ignore_valid_datetime.first.valid_datetime).to eq "2019/1/1"
              Employee.ignore_valid_datetime.first
            }
            expect(result.valid_datetime).to be_nil
          end
        end
      end

      context "relation object" do
        it do
          Company.valid_at("2019/1/1").tap { |m|
            expect(m.valid_datetime).to eq "2019/1/1"
            result = ActiveRecord::Bitemporal.valid_at("2019/2/2") {
              expect(m.valid_datetime).to eq "2019/1/1"
              expect(Employee.all.valid_datetime).to eq "2019/2/2"
              Employee.valid_at("2019/3/3").tap { |m|
                expect(m.valid_datetime).to eq "2019/3/3"
              }
              expect(Employee.ignore_valid_datetime.to_sql).not_to match %r/"valid_from" <= /
              expect(Employee.ignore_valid_datetime.to_sql).not_to match %r/"valid_to" > /
              expect(Employee.ignore_valid_datetime.first.valid_datetime).to eq "2019/2/2"
              Employee.ignore_valid_datetime.first
            }
            expect(result.valid_datetime).to be_nil
          }
        end
      end
    end

    describe "ActiveRecord::Bitemporal.valid_at!" do
      context "instance object" do
        let!(:company) { Company.create(name: "Company") }
        before do
          emp = company.employees.create(name: "Jane")
          emp.address = Address.create(name: "Address")
        end
        it do
          Company.includes(:employees, employees: :address).find_at_time(time_current, company.id).tap { |c|
            expect(c.valid_datetime).to eq time_current
            expect(c.employees.first.valid_datetime).to eq time_current
            expect(c.employees.first.address.valid_datetime).to eq time_current
            ActiveRecord::Bitemporal.valid_at!("2019/1/1") {
              expect(c.valid_datetime).to eq "2019/1/1"
              expect(c.employees.first.valid_datetime).to eq "2019/1/1"
              expect(c.employees.first.address.valid_datetime).to eq "2019/1/1"
            }
          }
        end
      end

      context "with ignore_valid_datetime" do
        it do
          result = ActiveRecord::Bitemporal.valid_at!("2019/1/1") {
            expect(Employee.ignore_valid_datetime.to_sql).not_to match %r/"valid_from" <= /
            expect(Employee.ignore_valid_datetime.to_sql).not_to match %r/"valid_to" > /
            expect(Employee.ignore_valid_datetime.first.valid_datetime).to eq "2019/1/1"
            Employee.ignore_valid_datetime.first
          }
          expect(result.valid_datetime).to be_nil
        end
      end

      context "relation object" do
        it do
          Company.valid_at("2019/1/1").tap { |m|
            expect(m.valid_datetime).to eq "2019/1/1"
            ActiveRecord::Bitemporal.valid_at!("2019/2/2") {
              expect(m.valid_datetime).to eq "2019/2/2"
              expect(Employee.all.valid_datetime).to eq "2019/2/2"
              Employee.valid_at("2019/3/3").tap { |m|
                expect(m.valid_datetime).to eq "2019/2/2"
              }
              expect(Employee.ignore_valid_datetime.to_sql).not_to match %r/"valid_from" <= /
              expect(Employee.ignore_valid_datetime.to_sql).not_to match %r/"valid_to" > /
            }
          }
        end
      end

      context "thread" do
        it do
          t1 = Thread.new {
            ActiveRecord::Bitemporal.with_bitemporal_option(value: 42) { |it|
              value = it.bitemporal_option[:value]
              sleep 0.1
              expect(value).to eq it.bitemporal_option[:value]
            }
          }

          t2 = Thread.new {
            ActiveRecord::Bitemporal.with_bitemporal_option(value: "homu") { |it|
              value = it.bitemporal_option[:value]
              sleep 0.3
              expect(value).to eq it.bitemporal_option[:value]
            }
          }

          t1.join
          t2.join

          expect(ActiveRecord::Bitemporal.bitemporal_option).to be_empty
        end
      end
    end

    describe "ActiveRecord::Bitemporal.ignore_valid_datetime" do
      it do
        ActiveRecord::Bitemporal.ignore_valid_datetime {
          expect(Employee.all.bitemporal_option).to include(ignore_valid_datetime: true)
        }
      end

      context "nexted call `.valid_at`" do
        before { Employee.create(valid_from: "2019/1/1") }
        it do
          ActiveRecord::Bitemporal.ignore_valid_datetime {
            ActiveRecord::Bitemporal.valid_at("2019/2/1") {
              expect(Employee.all.first.valid_datetime).to eq "2019/2/1"
              expect(Employee.all.to_sql).to match %r/"valid_from" <= '2019-02-01 00:00:00'/
              expect(Employee.all.to_sql).to match %r/"valid_to" > '2019-02-01 00:00:00'/
              expect(Employee.ignore_valid_datetime.to_sql).not_to match %r/"valid_from" <= /
              expect(Employee.ignore_valid_datetime.to_sql).not_to match %r/"valid_to" > /
            }
          }
        end
      end

      context "nexted call `.valid_at!`" do
        before { Employee.create(valid_from: "2019/1/1") }
        it do
          ActiveRecord::Bitemporal.ignore_valid_datetime {
            ActiveRecord::Bitemporal.valid_at!("2019/2/1") {
              expect(Employee.all.first.valid_datetime).to eq "2019/2/1"
              expect(Employee.all.to_sql).to match %r/"valid_from" <= '2019-02-01 00:00:00'/
              expect(Employee.all.to_sql).to match %r/"valid_to" > '2019-02-01 00:00:00'/
              expect(Employee.ignore_valid_datetime.to_sql).not_to match %r/"valid_from" <= /
              expect(Employee.ignore_valid_datetime.to_sql).not_to match %r/"valid_to" > /
            }
          }
        end
      end
    end

    describe ".ignore_valid_datetime" do
      before { Employee.create(valid_from: "2000/1/1") }
      it { expect(Employee.ignore_valid_datetime.bitemporal_option).to include(ignore_valid_datetime: true) }
      it { expect(Employee.ignore_valid_datetime.first.bitemporal_option.keys).not_to include(:ignore_valid_datetime) }

      context "call `.valid_at` before" do
        it { expect(Employee.valid_at("2019/1/1").ignore_valid_datetime.bitemporal_option).to include(ignore_valid_datetime: true) }
        it { expect(Employee.valid_at("2019/1/1").ignore_valid_datetime.first.valid_datetime).to be_nil }
      end

      context "call `.valid_at` later" do
        it { expect(Employee.ignore_valid_datetime.valid_at("2019/1/1").bitemporal_option).to include(ignore_valid_datetime: false, valid_datetime: "2019/1/1") }
        it { expect(Employee.ignore_valid_datetime.valid_at("2019/1/1").first.bitemporal_option).to include(valid_datetime: "2019/1/1") }
      end
    end
  end

  context ActiveRecord::Bitemporal::Persistence::EachAssociation do
    using ActiveRecord::Bitemporal::Persistence::EachAssociation
    let(:company) { Company.create(name: "Company") }
    before do
      company.employees.create(name: "Jane")
      company.employees.create(name: "Tom")
      company.employees.create(name: "Kevin")
    end

    it { expect(company.each_association.count).to eq 3 }
    it { expect(company.each_association.map(&:name)).to contain_exactly("Jane", "Tom", "Kevin") }

    it { expect(Company.find(company.id).each_association.count).to eq 3 }
    it { expect(Company.find(company.id).each_association.map(&:name)).to contain_exactly("Jane", "Tom", "Kevin") }

    context "with option `deep: true`" do
      before do
        company.employees.first.address = Address.create(city: "Tokyo")
        company.employees.second.address = Address.create(city: "Kyoto")
        company.employees.third.address = Address.create(city: "Saitama")
      end

      # MEMO: `belongs_to :comany` is alos included.
      it { expect(company.each_association(deep: true).count).to eq 7 }
      it { expect(company.employees.includes(:address).first.each_association(deep: true).count).to eq 7 }
      it { expect(Company.find(company.id).employees.first.each_association(deep: true).count).to eq 7 }
      it { expect(Company.find(company.id).each_association(deep: true).count).to eq 7 }
    end

    context "with option `only_cached: true`" do
      let(:opt) { { only_cached: true } }

      context "preloading" do
        it { expect(Company.includes(:employees).find(company.id).each_association(**opt).count).to eq 3 }
        it { expect(Company.includes(:employees).find(company.id).each_association(**opt).map(&:name)).to contain_exactly("Jane", "Tom", "Kevin") }
      end

      context "not preloading" do
        it { expect(company.each_association(**opt).count).to eq 3 }
        it { expect(company.each_association(**opt).map(&:name)).to contain_exactly("Jane", "Tom", "Kevin") }

        it { expect(Company.find(company.id).each_association(**opt).count).to eq 0 }
        it { expect(Company.find(company.id).each_association(**opt).map(&:name)).to be_empty }
      end

      context "with option `deep: true`" do
        let(:opt) { { deep: true, only_cached: true } }
        before do
          company.employees.first.address = Address.create(city: "Tokyo")
          company.employees.second.address = Address.create(city: "Kyoto")
          company.employees.third.address = Address.create(city: "Saitama")
        end

        context "preloading" do
          it { expect(company.employees.includes(:address).first.each_association(**opt).count).to eq 1 }

          it { expect(Company.includes(:employees).find(company.id).each_association(**opt).count).to eq 3 }
          it { expect(Company.includes(:employees).find(company.id).employees.first.each_association(**opt).count).to eq 0 }

          it { expect(Company.includes(:employees, employees: :address).find(company.id).each_association(**opt).count).to eq 6 }
          it { expect(Company.includes(:employees, employees: :address).find(company.id).employees.first.each_association(**opt).count).to eq 1 }
          it { expect(Company.includes(:employees, employees: :company).find(company.id).each_association(**opt).count).to eq 4 }
        end

        context "not preloading" do
          it { expect(company.employees.first.each_association(**opt).count).to eq 0 }

          it { expect(Company.find(company.id).each_association(**opt).count).to eq 0 }
          it { expect(Company.find(company.id).employees.first.each_association(**opt).count).to eq 0 }
        end
      end
    end
  end

  context "with multi thread", use_truncation: true do
    describe "#update" do
      let!(:company) { Company.create!(name: "Company") }
      let!(:company2) { Company.create!(name: "Company") }
      subject do
        thread_new = proc { |id|
          Thread.new(id) { |id|
            ActiveRecord::Base.connection_pool.with_connection do
              company = Company.find(id)
              if !company.update(name: "Company2")
                expect(company.errors[:bitemporal_id]).to include("has already been taken")
              end
            end
          }
        }
        proc do
          [
            thread_new.call(company.id),
            thread_new.call(company.id),
            thread_new.call(company.id),
            thread_new.call(company2.id),
            thread_new.call(company2.id),
            thread_new.call(company2.id),
          ].each { |t| t.join(3) }
        end
      end
      it { is_expected.to change { Company.ignore_valid_datetime.count }.by(2) }
      (1..10).each do
        it do
          subject.call
          com1, com2 = Company.ignore_valid_datetime.bitemporal_for(company.id).order(:valid_from).last(2)
          expect(com1.valid_to).not_to eq com2.valid_to
        end
      end
    end

    describe "#save" do
      context "multi threading" do
        let!(:company) { Company.create!(name: "Company") }
        let!(:company2) { Company.create!(name: "Company") }
        subject do
          thread_new = proc { |id|
            Thread.new(id) { |id|
              ActiveRecord::Base.connection_pool.with_connection do
                company = Company.find(id)
                company.name = "Company2"
                if !company.save
                  expect(company.errors[:bitemporal_id]).to include("has already been taken")
                end
              end
            }
          }
          proc do
            [
              thread_new.call(company.id),
              thread_new.call(company.id),
              thread_new.call(company.id),
              thread_new.call(company2.id),
              thread_new.call(company2.id),
              thread_new.call(company2.id),
            ].each { |t| t.join(3) }
          end
        end
        it { is_expected.to change { Company.ignore_valid_datetime.count }.by(2) }
        it do
          subject.call
          com1, com2 = Company.ignore_valid_datetime.bitemporal_for(company.id).order(:valid_from).last(2)
          expect(com1.valid_to).not_to eq com2.valid_to
        end
      end
    end

    context "wiht lock! by application side" do
      let!(:company) { Company.create!(name: "Company") }
      let!(:company2) { Company.create!(name: "Company") }
      subject do
        thread_new = proc { |id|
          Thread.new(id) { |id|
            ActiveRecord::Base.connection_pool.with_connection do
              ActiveRecord::Base.transaction do
                Company.where(bitemporal_id: id).lock!.pluck(:id)
                company = Company.find(id)
                company.name += "!"
                if !company.save
                  expect(company.errors[:bitemporal_id]).to include("has already been taken")
                end
              end
            end
          }
        }
        proc do
          [
            thread_new.call(company.id),
            thread_new.call(company.id),
            thread_new.call(company.id),
            thread_new.call(company2.id),
            thread_new.call(company2.id),
          ].each { |t| t.join(3) }
        end
      end
      (1..10).each do
        it do
          subject.call
          com1, com2 = Company.ignore_valid_datetime.bitemporal_for(company.id).order(:valid_from).last(2)
          expect(com1.valid_to).not_to eq com2.valid_to
        end
      end
    end
  end

  describe ".scope_for_create" do
    subject { relation.scope_for_create }

    context "call after `where`" do
      let(:relation) { Employee.where(id: 1, bitemporal_id: 3) }
      it { is_expected.to include("id" => 1, "bitemporal_id" => 3) }
    end

    context "call after `associations.where`" do
      let(:relation) { Company.create!.employees.where(id: 1, bitemporal_id: 3) }
      it { is_expected.to include("id" => 1, "bitemporal_id" => 3) }
    end
  end

  describe "build association" do
    context "belong_to associations" do
      let(:target_obj) { Company.create.employees.create }
      subject { target_obj.build_company }

      it { is_expected.to have_attributes(id: nil, bitemporal_id: nil) }

      context "with `bitemporal_id:" do
        subject { target_obj.build_company(bitemporal_id: 3) }
        it { is_expected.to have_attributes(id: nil, bitemporal_id: 3) }
      end
    end

    context "has_one associations" do
      let(:target_obj) { Employee.create }
      subject { target_obj.build_address }

      it { is_expected.to have_attributes(id: nil, bitemporal_id: nil) }

      context "with `bitemporal_id:" do
        subject { target_obj.build_address(bitemporal_id: 3) }
        it { is_expected.to have_attributes(id: nil, bitemporal_id: 3) }
      end
    end
  end
end
