# frozen_string_literal: true

require 'spec_helper'

class EmployeeWithUniquness < Employee
  validates :name, uniqueness: true
end

RSpec.describe "force_update" do
  let(:time_current) { Time.current.round(6) }
  let(:_01_01) { "2020/01/01".in_time_zone }
  let(:_02_01) { "2020/02/01".in_time_zone }
  let(:_03_01) { "2020/03/01".in_time_zone }
  let(:_04_01) { "2020/04/01".in_time_zone }
  let(:_05_01) { "2020/05/01".in_time_zone }
  let(:_06_01) { "2020/06/01".in_time_zone }
  let(:_07_01) { "2020/07/01".in_time_zone }
  let(:_08_01) { "2020/08/01".in_time_zone }
  let(:_12_31) { "9999/12/31".in_time_zone }

  describe "#force_update" do
    let(:target) { Employee.find_at_time(_04_01, @target.id) }
    define_method(:target_histories) { Employee.ignore_valid_datetime.bitemporal_for(target.id).order(:valid_from) }
    define_method(:target_history_values) {
      target_histories.pluck(:valid_from, :valid_to, :name)
    }

    # Before:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|------- target ------|-------------------------|-------------------------|
    #
    before do
      ActiveRecord::Bitemporal.valid_at(_01_01) { @target = Employee.create(name: "A") }
      ActiveRecord::Bitemporal.valid_at(_03_01) { @target.update!(name: "B") }
      ActiveRecord::Bitemporal.valid_at(_05_01) { @target.update!(name: "C") }
      ActiveRecord::Bitemporal.valid_at(_07_01) { @target.update!(name: "D") }
    end

    subject {
      target.force_update { |record|
        record.update!(valid_from: valid_from, valid_to: valid_to, name: "X")
      }
    }

    # Before:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|------- target ------|-------------------------|-------------------------|
    #
    # After:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|*********************|-------------------------|-------------------------|
    #                           ^                     ^
    #                       valid_from             valid_to
    #
    context "valid_from: 03/01, valid_to: 05/01" do
      let(:valid_from) { _03_01 }
      let(:valid_to) { _05_01 }

      it do
        expect { subject }.to change { target_history_values }.to [
          [_01_01, _03_01, "A"],
          [_03_01, _05_01, "X"],
          [_05_01, _07_01, "C"],
          [_07_01, _12_31, "D"]
        ]
      end
    end

    # Before:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|------- target ------|-------------------------|-------------------------|
    #
    # After:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |----------|*********************************************|------------|-------------------------|
    #                ^                                             ^
    #            valid_from                                     valid_to
    #
    context "valid_from: 02/01, valid_to: 05/01" do
      let(:valid_from) { _02_01 }
      let(:valid_to) { _06_01 }

      it do
        expect { subject }.to change { target_history_values }.to [
          [_01_01, _02_01, "A"],
          [_02_01, _06_01, "X"],
          [_06_01, _07_01, "C"],
          [_07_01, _12_31, "D"]
        ]
      end
    end

    # Before:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|------- target ------|-------------------------|-------------------------|
    #
    # After:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |*********************************************************************|-------------------------|
    #     ^                                                                     ^
    # valid_from                                                             valid_to
    #
    context "valid_from: 02/01, valid_to: 05/01" do
      let(:valid_from) { _01_01 }
      let(:valid_to) { _07_01 }

      it do
        expect { subject }.to change { target_history_values }.to [
          [_01_01, _07_01, "X"],
          [_07_01, _12_31, "D"]
        ]
      end
    end

    # Before:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|------- target ------|-------------------------|-------------------------|
    #
    # After:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|          |*************************************************|------------|
    #                                      ^                                                 ^
    #                                  valid_from                                         valid_to
    #
    context "valid_from: 03/01, valid_to: 05/01" do
      let(:valid_from) { _04_01 }
      let(:valid_to) { _08_01 }

      it do
        expect { subject }.to change { target_history_values }.to [
          [_01_01, _03_01, "A"],
          [_04_01, _08_01, "X"],
          [_08_01, _12_31, "D"]
        ]
      end
    end

    # Before:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|------- target ------|-------------------------|-------------------------|
    #
    # After:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|**********|          |-------------------------|-------------------------|
    #                           ^          ^
    #                       valid_from  valid_to
    #
    context "valid_from: 03/01, valid_to: 05/01" do
      let(:valid_from) { _03_01 }
      let(:valid_to) { _04_01 }

      it do
        expect { subject }.to change { target_history_values }.to [
          [_01_01, _03_01, "A"],
          [_03_01, _04_01, "X"],
          [_05_01, _07_01, "C"],
          [_07_01, _12_31, "D"]
        ]
      end
    end
  end

  describe "uniqueness" do
    let(:target) { EmployeeWithUniquness.find_at_time(_04_01, @target.id) }
    define_method(:target_histories) { EmployeeWithUniquness.ignore_valid_datetime.bitemporal_for(target.id).order(:valid_from) }
    define_method(:target_history_values) {
      target_histories.pluck(:valid_from, :valid_to, :name)
    }

    #
    # === Current ===
    #
    # Before:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|---- target : X -----|-------------------------|-------------------------|
    #
    #
    # === Other ===
    #
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |--- X ----|-------------------- Y ----------------------|------------X -----------|---- Y -----|
    #
    before do
      other = nil

      ActiveRecord::Bitemporal.valid_at(_01_01) { other = EmployeeWithUniquness.create(name: "X") }
      ActiveRecord::Bitemporal.valid_at(_02_01) { other.update!(name: "Y") }

      ActiveRecord::Bitemporal.valid_at(_01_01) { @target = EmployeeWithUniquness.create(name: "A") }
      ActiveRecord::Bitemporal.valid_at(_03_01) { @target.update!(name: "X") }
      ActiveRecord::Bitemporal.valid_at(_05_01) { @target.update!(name: "C") }
      ActiveRecord::Bitemporal.valid_at(_07_01) { @target.update!(name: "D") }

      ActiveRecord::Bitemporal.valid_at(_06_01) { other.update!(name: "X") }
      ActiveRecord::Bitemporal.valid_at(_08_01) { other.update!(name: "Y") }
    end

    subject {
      target.force_update { |record|
        record.update!(valid_from: valid_from, valid_to: valid_to, name: "X")
      }
    }

    #
    # === Current ===
    #
    # Before:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|---- target : X -----|-------------------------|-------------------------|
    #
    # After:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |----------|*********************************************|------------|-------------------------|
    #
    #
    # === Other ===
    #
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |--- X ----|-------------------- Y ----------------------|------------X -----------|---- Y -----|
    #
    context "valid_from: 02/01, valid_to: 06/01" do
      let(:valid_from) { _02_01 }
      let(:valid_to) { _06_01 }

      it { expect { subject }.not_to raise_error }
    end

    #
    # === Current ===
    #
    # Before:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|---- target : X -----|-------------------------|-------------------------|
    #
    # After:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|***********************************************|-------------------------|
    #
    #
    # === Other ===
    #
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |--- X ----|-------------------- Y ----------------------|------------X -----------|---- Y -----|
    #
    context "valid_from: 03/01, valid_to: 07/01" do
      let(:valid_from) { _03_01 }
      let(:valid_to) { _08_01 }

      it { expect { subject }.to raise_error(ActiveRecord::RecordInvalid) }
    end

    #
    # === Current ===
    #
    # Before:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|---- target : X -----|-------------------------|-------------------------|
    #
    # After:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|************************************************************|------------|
    #
    #
    # === Other ===
    #
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |--- X ----|-------------------- Y ----------------------|------------X -----------|---- Y -----|
    #
    context "valid_from: 03/01, valid_to: 08/01" do
      let(:valid_from) { _03_01 }
      let(:valid_to) { _08_01 }

      it { expect { subject }.to raise_error(ActiveRecord::RecordInvalid) }
    end

    #
    # === Current ===
    #
    # Before:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|---- target : X -----|-------------------------|-------------------------|
    #
    # After:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|*************************************************************************|
    #
    #
    # === Other ===
    #
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |--- X ----|-------------------- Y ----------------------|------------X -----------|---- Y -----|
    #
    context "valid_from: 03/01, valid_to: 9999/12/31" do
      let(:valid_from) { _03_01 }
      let(:valid_to) { _12_31 }

      it { expect { subject }.to raise_error(ActiveRecord::RecordInvalid) }
    end

    #
    # === Current ===
    #
    # Before:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|---- target : X -----|-------------------------|-------------------------|
    #
    # After:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |----------|********************************|---------------------------------------------------|
    #
    #
    # === Other ===
    #
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |--- X ----|-------------------- Y ----------------------|------------X -----------|---- Y -----|
    #
    context "valid_from: 02/01, valid_to: 05/01" do
      let(:valid_from) { _02_01 }
      let(:valid_to) { _05_01 }

      it { expect { subject }.not_to raise_error }
    end

    #
    # === Current ===
    #
    # Before:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|---- target : X -----|-------------------------|-------------------------|
    #
    # After:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |*******************************************|---------------------------------------------------|
    #
    #
    # === Other ===
    #
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |--- X ----|-------------------- Y ----------------------|------------X -----------|---- Y -----|
    #
    context "valid_from: 01/01, valid_to: 05/01" do
      let(:valid_from) { _01_01 }
      let(:valid_to) { _05_01 }

      it { expect { subject }.to raise_error(ActiveRecord::RecordInvalid) }
    end

    #
    # === Current ===
    #
    # Before:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|---- target : X -----|-------------------------|-------------------------|
    #
    # After:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     ********************************************|---------------------------------------------------|
    #
    #
    # === Other ===
    #
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |--- X ----|-------------------- Y ----------------------|------------X -----------|---- Y -----|
    #
    context "valid_from: 1950/01/01, valid_to: 05/01" do
      let(:valid_from) { "1950/01/01" }
      let(:valid_to) { _05_01 }

      it { expect { subject }.to raise_error(ActiveRecord::RecordInvalid) }
    end

    #
    # === Current ===
    #
    # Before:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |---------------------|---- target : X -----|-------------------------|-------------------------|
    #
    # After:
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     ************************************************************************************************|
    #
    #
    # === Other ===
    #
    #   01/01      02/01      03/01      04/01      05/01        06/01        07/01        08/01      9999/12/31
    #     |--- X ----|-------------------- Y ----------------------|------------X -----------|---- Y -----|
    #
    context "valid_from: 1950/01/01, valid_to: 9999/12/31" do
      let(:valid_from) { "1950/01/01" }
      let(:valid_to) { _12_31 }

      it { expect { subject }.to raise_error(ActiveRecord::RecordInvalid) }
    end
  end
end
