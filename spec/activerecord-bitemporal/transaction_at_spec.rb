require 'spec_helper'

RSpec.describe "transaction_at" do
  describe "fix `created_at` and `deleted_at`" do
    let(:company) { Company.create(name: "Company1") }
    define_method(:company_all) { Company.ignore_valid_datetime.within_deleted.bitemporal_for(company.id).order(:created_at) }

    before do
      # Created any records
      company.update!(name: "Company2")
      company.force_update { |it| it.update!(name: "Company3") }
    end

    context "updated" do
      it "prev.deleted_at to equal next.created_at" do
        company.update!(name: "NewCompany")
        expect(company_all[-3].deleted_at).to eq(company_all[-2].created_at)
                                         .and(eq(company_all[-1].created_at))
      end

      it "updated `created_at`" do
        expect { company.update(name: "Company4").to change { company.created_at } }
      end

      context "with `#force_update`" do
        it do
          company.force_update { |it| it.update!(name: "NewCompany") }
          expect(company_all[-2].deleted_at).to eq(company_all[-1].created_at)
        end
      end
    end

    context "deleted" do
      it do
        company.reload.destroy
        expect(company_all[-2].deleted_at).to eq(company_all[-1].created_at)
      end
    end
  end

  describe "validation `created_at` `deleted_at`" do
    let(:time_current) { Time.current.round(6) }
    subject { employee }
    context "with `created_at` and `deleted_at`" do
      let(:employee) { Employee.new(name: "Jane", created_at: created_at, deleted_at: deleted_at) }
      context "`created_at` < `deleted_at`" do
        let(:created_at) { time_current }
        let(:deleted_at) { created_at + 10.days }
        it { is_expected.to be_valid }
      end

      context "`created_at` > `deleted_at`" do
        let(:created_at) { deleted_at + 10.days }
        let(:deleted_at) { time_current }
        it { is_expected.to be_invalid }
      end

      context "`created_at` == `deleted_at`" do
        let(:created_at) { time_current }
        let(:deleted_at) { created_at }
        it { is_expected.to be_invalid }
      end

      context "`created_at` is `nil`" do
        let(:created_at) { nil }
        let(:deleted_at) { time_current }
        it { is_expected.to be_valid }
      end

      context "`deleted_at` is `nil`" do
        let(:created_at) { time_current }
        let(:deleted_at) { nil }
        it { is_expected.to be_valid }
      end

      context "`created_at` and `deleted_at` is `nil`" do
        let(:created_at) { nil }
        let(:deleted_at) { nil }
        it { is_expected.to be_valid }
      end
    end

    context "with `created_at`" do
      let(:employee) { Employee.new(name: "Jane", created_at: created_at) }
      let(:created_at) { time_current }
      it { is_expected.to be_valid }
    end

    context "with `deleted_at`" do
      let(:employee) { Employee.new(name: "Jane", deleted_at: deleted_at) }
      let(:deleted_at) { time_current + 10.days }
      it { is_expected.to be_valid }
    end

    context "blank `created_at` and `deleted_at`" do
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
          EmployeeWithUniquness.create!(name: "Jane", created_at: active_from, deleted_at: active_to, valid_from: valid_from, valid_to: valid_to)
        end
      end

      shared_examples "valid uniqueness" do
        include_context "define active model"
        subject { EmployeeWithUniquness.new(name: "Jane", created_at: new_from, deleted_at: new_to, valid_from: valid_from, valid_to: valid_to) }
        it { is_expected.to be_valid }
      end

      shared_examples "invalid uniqueness" do
        include_context "define active model"
        subject { EmployeeWithUniquness.new(name: "Jane", created_at: new_from, deleted_at: new_to, valid_from: valid_from, valid_to: valid_to) }
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
        let(:new_to) { nil }
      end

      # active transaction time : |<-----------------------> Infinite
      # new transaction time    :        |<---------->|
      it_behaves_like "invalid uniqueness" do
        let(:new_from) { active_from + 5.days }
        let(:new_to) { new_from + 5.days }
        let(:active_to) { nil }
      end

      # active transaction time : |<-----------------------> Infinite
      # new transaction time    :        |<-----------------------> Infinite
      it_behaves_like "invalid uniqueness" do
        let(:new_from) { active_from + 5.days }
        let(:new_to) { nil }
        let(:active_to) { nil }
      end
    end

    context "have an active models" do
      shared_context "define active models" do
        let(:active1_from) { time_current }
        let(:active1_to) { active1_from + 10.days }

        let(:active2_from) { active1_from + 40.days }
        let(:active2_to) { active2_from + 10.days }

        before do
          EmployeeWithUniquness.create!(name: "Jane", created_at: active1_from, deleted_at: active1_to)
          EmployeeWithUniquness.create!(name: "Jane", created_at: active2_from, deleted_at: active2_to)
        end
      end

      shared_examples "valid uniqueness" do
        include_context "define active models"
        subject { EmployeeWithUniquness.new(name: "Jane", created_at: new_from, deleted_at: new_to) }
        it { is_expected.to be_valid }
      end

      shared_examples "invalid uniqueness" do
        include_context "define active models"
        subject { EmployeeWithUniquness.new(name: "Jane", created_at: new_from, deleted_at: new_to) }
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
          EmployeeWithUniquness.create!(name: "Tom", created_at: "1982/12/02", deleted_at: "2001/03/24")
        end
        it { is_expected.not_to raise_error }
      end

      context "exists future model" do
        before do
          EmployeeWithUniquness.create!(name: "Tom", created_at: Time.current + 10.days)
        end
        it { is_expected.to raise_error ActiveRecord::RecordInvalid }
      end
    end

    context "and `valid_from`" do
      before do
        EmployeeWithUniquness.create(name: "Jane", valid_from: "2019/1/10", valid_to: "2019/20")
      end
      subject { EmployeeWithUniquness.new(name: "Jane", valid_from: "2019/1/15").valid_at("2019/1/30", &:save) }
    end

    context "`valid_datetime` out of range `valid_from` ~ `valid_to`" do
      it { is_expected.to be_truthy }

      context "empty records" do
        before { EmployeeWithUniquness.destroy_all }
        subject { EmployeeWithUniquness.new(valid_from: "9999/1/10").valid_at("9999/1/1", &:save) }
        it { is_expected.to be_truthy }
      end
    end

    context "duplicated `valid_from` `valid_to` with non set `created_at`" do
      let(:created_at) { "2019/04/01".to_time }
      let(:deleted_at) { "2019/10/01".to_time }
      let(:valid_from) { "2019/01/01".to_time }
      let(:valid_to) { "2019/06/01".to_time }
      before do
        EmployeeWithUniquness.create!(created_at: created_at, deleted_at: deleted_at, valid_from: valid_from, valid_to: valid_to, name: "Jane")
      end

      context "current time in created_at ~ deleted_at" do
        it do
          Timecop.freeze(created_at + 1.days) {
            emp = EmployeeWithUniquness.new(valid_from: valid_from, valid_to: valid_to, name: "Jane")
            expect(emp).to be_invalid
          }
        end
      end

      context "current time in created_at ~ deleted_at" do
        it do
          Timecop.freeze(created_at + 1000.days) {
            emp = EmployeeWithUniquness.new(valid_from: valid_from, valid_to: valid_to, name: "Jane")
            expect(emp).to be_valid
          }
        end
      end
    end
  end
end
