# frozen_string_literal: true

require 'spec_helper'

class EmployeeWithUniquness < Employee
  validates :name, uniqueness: true
end

class EmployeeWithUniqunessAndScope < Employee
  validates :name, uniqueness: { scope: :emp_code }
end

class EmployeeWithUniqunessAndMessage < Employee
  validates :name, uniqueness: { message: "is duplicated" }
end

RSpec.describe ActiveRecord::Bitemporal::Uniqueness do
  # MEMO: Intentionally shift test time
  let(:time_current) { Time.current.round(6) + 10.years }

  describe "hook UniquenessValidator" do
    subject { model.const_get(:UniquenessValidator).ancestors }

    context "included ActiveRecord::Bitemporal model" do
      let(:model) { Employee }
      it { is_expected.to include ActiveRecord::Bitemporal::Uniqueness }
    end

    context "non included ActiveRecord::Bitemporal model" do
      let(:model) { EmployeeWithoutBitemporal }
      it { is_expected.not_to include ActiveRecord::Bitemporal::Uniqueness }
    end
  end

  describe EmployeeWithUniquness do
    context "have an active model" do
      shared_context "define active model" do
        let(:active_from) { time_current }
        let(:active_to) { active_from + 10.days }
        before do
          EmployeeWithUniquness.create!(name: "Jane", valid_from: active_from, valid_to: active_to)
        end
      end

      shared_examples "valid uniqueness" do
        include_context "define active model"
        subject { EmployeeWithUniquness.new(name: "Jane", valid_from: new_from, valid_to: new_to) }
        it { is_expected.to be_valid }
      end

      shared_examples "invalid uniqueness" do
        include_context "define active model"
        subject { EmployeeWithUniquness.new(name: "Jane", valid_from: new_from, valid_to: new_to) }
        it { is_expected.to be_invalid }
      end

      # active valid time :                 |<---------->|
      # new valid time    : |<---------->|
      it_behaves_like "valid uniqueness" do
        let(:new_from) { active_from - 12.days }
        let(:new_to) { active_to - 12.days }
      end

      # active valid time :              |<---------->|
      # new valid time    : |<---------->|
      it_behaves_like "valid uniqueness" do
        let(:new_from) { new_to - 10.days }
        let(:new_to) { active_from }
      end

      # active valid time :        |<---------->|
      # new valid time    : |<---------->|
      it_behaves_like "invalid uniqueness" do
        let(:new_from) { active_from - 5.days }
        let(:new_to) { active_to - 5.days }
      end

      # active valid time :        |<---------->|
      # new valid time    : |<----------------->|
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

      # active valid time : |<---------->|
      # new valid time    : |<----------------->|
      it_behaves_like "invalid uniqueness" do
        let(:new_from) { active_from }
        let(:new_to) { active_to + 15.days }
      end

      # active valid time : |<---------->|
      # new valid time    :        |<---------->|
      it_behaves_like "invalid uniqueness" do
        let(:new_from) { active_from + 5.days }
        let(:new_to) { active_to + 5.days }
      end

      # active valid time : |<---------->|
      # new valid time    :              |<---------->|
      it_behaves_like "valid uniqueness" do
        let(:new_from) { active_to }
        let(:new_to) { new_from + 10.days }
      end

      # active valid time : |<---------->|
      # new valid time    :                 |<---------->|
      it_behaves_like "valid uniqueness" do
        let(:new_from) { active_from + 12.days }
        let(:new_to) { active_to + 12.days }
      end
    end

    context "have an active models" do
      shared_context "define active models" do
        let(:active1_from) { time_current }
        let(:active1_to) { active1_from + 10.days }

        let(:active2_from) { active1_from + 40.days }
        let(:active2_to) { active2_from + 10.days }

        before do
          EmployeeWithUniquness.create!(name: "Jane", valid_from: active1_from, valid_to: active1_to)
          EmployeeWithUniquness.create!(name: "Jane", valid_from: active2_from, valid_to: active2_to)
        end
      end

      shared_examples "valid uniqueness" do
        include_context "define active models"
        subject { EmployeeWithUniquness.new(name: "Jane", valid_from: new_from, valid_to: new_to) }
        it { is_expected.to be_valid }
      end

      shared_examples "invalid uniqueness" do
        include_context "define active models"
        subject { EmployeeWithUniquness.new(name: "Jane", valid_from: new_from, valid_to: new_to) }
        it { is_expected.to be_invalid }
      end

      # active1 valid time : |<---------->|
      # active2 valid time :                                 |<---------->|
      # new valid time     :                 |<---------->|
      it_behaves_like "valid uniqueness" do
        let(:new_from) { active1_to + 2.days }
        let(:new_to) { new_from + 10.days }
      end

      # active1 valid time :                 |<---------->|
      # active2 valid time :                                 |<---------->|
      # new valid time     : |<---------->|
      it_behaves_like "valid uniqueness" do
        let(:new_from) { new_to - 10.days }
        let(:new_to) { active1_from - 2.days }
      end

      # active1 valid time : |<---------->|
      # active2 valid time :                |<---------->|
      # new valid time     :                               |<---------->|
      it_behaves_like "valid uniqueness" do
        let(:new_from) { active2_to + 2.days }
        let(:new_to) { new_from + 10.days }
      end

      # active1 valid time : |<---------->|
      # active2 valid time :          |<---------->|
      # new valid time     :                    |<---------->|
      it_behaves_like "invalid uniqueness" do
        let(:new_from) { active1_to - 2.days }
        let(:new_to) { active2_from + 2.days }
      end

      # active1 valid time : |<---------->|
      # active2 valid time :              |<---------->|
      # new valid time     :                           |<---------->|
      it_behaves_like "valid uniqueness" do
        let(:new_from) { active2_to }
        let(:new_to) { new_from + 10.days }
      end
    end

    describe "#update" do
      let(:employee) { EmployeeWithUniquness.create!(name: "Jane", emp_code: "000") }
      context "any update" do
        it do
          expect { employee.update(emp_code: "001") }.to change(employee, :swapped_id)
          expect { employee.update(emp_code: "002") }.to change(employee, :swapped_id)
          expect { employee.update(emp_code: "003") }.to change(employee, :swapped_id)
        end
      end

      context "update to name" do
        subject { -> { employee.update!(name: "Tom") } }

        context "exitst other records" do
          context "same name" do
            let!(:other) { EmployeeWithUniquness.create!(name: "Jane").tap { |m| m.update!(name: "Tom") } }
            it { is_expected.to raise_error ActiveRecord::RecordInvalid }
          end
          context "other name" do
            let!(:other) { EmployeeWithUniquness.create!(name: "Mami").tap { |m| m.update!(name: "Homu") }  }
            it { is_expected.not_to raise_error }
            it { is_expected.to change { employee.reload.name }.from("Jane").to("Tom") }
          end
        end

        context "after updating other record" do
          let!(:other) { EmployeeWithUniquness.create!(name: "Jane").tap { |m| m.update!(name: "Tom") } }
          before do
            other.update!(name: "Homu")
          end
          it { is_expected.not_to raise_error }
          it { is_expected.to change { employee.reload.name }.from("Jane").to("Tom") }

          context "with `valid_at`" do
            subject { -> { employee.valid_at(Time.current - 1.days) { |m| m.update!(name: "Tom") } } }
            it { is_expected.to raise_error ActiveRecord::RecordInvalid }
          end
        end

        context "after destroying other record" do
          let!(:other) { EmployeeWithUniquness.create!(name: "Jane").tap { |m| m.update!(name: "Tom") } }
          before do
            other.destroy
          end
          it { is_expected.not_to raise_error }
          it { is_expected.to change { employee.reload.name }.from("Jane").to("Tom") }

          context "with `valid_at`" do
            subject { -> { employee.valid_at(Time.current - 1.days) { |m| m.update!(name: "Tom") } } }
            it { is_expected.to raise_error ActiveRecord::RecordInvalid }
          end
        end
      end
    end

    describe "#dup" do
      let(:employee) { EmployeeWithUniquness.create!(name: "Jane").tap { |it| it.update(name: "Tom") } }
      subject { employee.dup.save  }
      it { is_expected.to be_falsey }
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
          EmployeeWithUniquness.create!(name: "Tom", valid_from: "1982/12/02", valid_to: "2001/03/24")
        end
        it { is_expected.not_to raise_error }
      end
    end

    context "with `#valid_at`" do
      let(:employee) { Timecop.freeze("2019/2/1") { EmployeeWithUniquness.create!(name: "Tom") } }
      before do
        Timecop.freeze("2019/3/1") { employee.update(name: "Jane") }
        Timecop.freeze("2019/4/1") { employee.update(name: "Kevin") }
      end
      it do
        Timecop.freeze("2019/5/1") { employee.valid_at("2019/1/1") { |m|
          m.name = "Tom"
          expect(m).to be_valid
        } }
      end
      it do
        Timecop.freeze("2019/5/1") { employee.valid_at("2019/1/1") { |m|
          m.name = "Jane"
          expect(m).to be_valid
        } }
      end

      context "exists other record" do
        before { EmployeeWithUniquness.create!(name: "Homu", valid_from: "2019/1/10", valid_to: "2019/1/20") }
        it do
          Timecop.freeze("2019/3/1") { employee.valid_at("2019/1/1") { |m|
            m.name = "Homu"
            expect(m).to be_invalid
          } }
        end
      end
    end

    context "and `valid_from`" do
      before do
        EmployeeWithUniquness.create(name: "Jane", valid_from: "2019/1/10", valid_to: "2019/1/20")
      end
      subject { EmployeeWithUniquness.new(name: "Jane", valid_from: "2019/1/15").valid_at("2019/1/30", &:save) }
      it { is_expected.to be_falsey }
    end

    context "`valid_datetime` out of range `valid_from` ~ `valid_to`" do
      it { is_expected.to be_truthy }

      context "empty records" do
        before { EmployeeWithUniquness.destroy_all }
        subject { EmployeeWithUniquness.new(valid_from: "9999/1/10").valid_at("9999/1/1", &:save) }
        it { is_expected.to be_truthy }
      end
    end

    context "`valid_at` is duplicated in past history" do
      let(:record) {
        employee = EmployeeWithUniquness.create(name: "A", valid_from: "2000/01/01")
        employee.update!(name: "B")
        employee
      }
      subject { record.valid_at("2010/01/01", &:valid?) }
      it { is_expected.to be_falsey }
    end
  end

  describe EmployeeWithUniqunessAndScope do
    let(:valid_from) { time_current }
    let(:valid_to) { valid_from + 10.days }
    let!(:active) {
      EmployeeWithUniqunessAndScope.create!(name: "Jane", emp_code: "emp-001", valid_from: valid_from, valid_to: valid_to)
    }

    subject {
      EmployeeWithUniqunessAndScope.new(name: new_name, emp_code: new_emp_code, valid_from: valid_from, valid_to: valid_to)
    }

    context "duplicate `name` and `emp_code`" do
      let(:new_name) { active.name }
      let(:new_emp_code) { active.emp_code }
      it { is_expected.to be_invalid }
    end

    context "duplicate `name`" do
      let(:new_name) { active.name }
      let(:new_emp_code) { "emp-002" }
      it { is_expected.to be_valid }
    end

    context "duplicate `emp_code`" do
      let(:new_name) { "Tom" }
      let(:new_emp_code) { active.emp_code }
      it { is_expected.to be_valid }
    end
  end

  context EmployeeWithUniqunessAndMessage do
    let(:valid_from) { time_current }
    let(:valid_to) { valid_from + 10.days }
    let!(:active) {
      EmployeeWithUniqunessAndMessage.create!(name: "Jane", valid_from: valid_from, valid_to: valid_to)
    }
    subject {
      EmployeeWithUniqunessAndMessage.create(name: "Jane", valid_from: valid_from, valid_to: valid_to).errors.full_messages
    }
    it { is_expected.to include "Name is duplicated" }
  end
end
