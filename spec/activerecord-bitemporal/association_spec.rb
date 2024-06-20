# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "Association" do
  let(:time_current) { Time.current.round(6) }

  describe "BTDM has many non BTDM" do
    context "call employee.update" do
      let!(:employee) { Employee.create!(name: "Mami").tap { |it| it.update(name: "Jane") } }
      let!(:tokyo) { employee.address_without_bitemporal = AddressWithoutBitemporal.create!(city: "Tokyo") }

      subject { employee.update!(name: "Tom") }
      it { expect { subject }.to change { tokyo.reload.employee.name }.from("Jane").to("Tom") }
      it { expect { subject }.to change { AddressWithoutBitemporal.find_by(city: "Tokyo").employee.name }.from("Jane").to("Tom") }

      context "any call" do
        it do
          expect(AddressWithoutBitemporal.find_by(city: "Tokyo").employee.name).to eq "Jane"

          employee.update(name: "Homu")
          expect(AddressWithoutBitemporal.find_by(city: "Tokyo").employee.name).to eq "Homu"

          employee.update(name: "Mami")
          expect(AddressWithoutBitemporal.find_by(city: "Tokyo").employee.name).to eq "Mami"
        end
      end
    end

    describe "get employee_without_bitemporals" do
      let!(:company) { Company.create!(name: "Company").tap { |it| it.update(name: "Company2") } }
      context "with any updated" do
        subject { company.employee_without_bitemporals.pluck(:name) }
        before do
          company.update(name: "Company3")
          EmployeeWithoutBitemporal.create(name: "Jane", company_id: company.id)
          EmployeeWithoutBitemporal.create(name: "Tom", company_id: company.id)
          company.update(name: "Company4")
        end
        it { is_expected.to contain_exactly("Jane", "Tom") }
      end
    end

    describe "preload" do
      before do
        Company.create!(name: "Company1").employee_without_bitemporals.create!(name: "Jane")
        Company.create!(name: "Company2").employee_without_bitemporals.create!(name: "Tom")
        Company.create!(name: "Company3").employee_without_bitemporals.create!(name: "Tom")
        Company.create!(name: "Company4")
      end
      it { expect(Company.includes(:employee_without_bitemporals).all.size).to eq 4 }
      it { expect(Company.joins(:employee_without_bitemporals).all.size).to eq 3 }
      it { expect(Company.includes(:employee_without_bitemporals).where(employee_without_bitemporals: { name: "Tom"}).count).to eq 2 }
    end

    describe "eager_load" do
      before do
        company = Company.create!(name: "Company")
        company.employee_without_bitemporals.create!(name: "Jane")
        company.employee_without_bitemporals.create!(name: "Tom")
      end

      context "w/o eager_load" do
        let(:company) { Company.find_by(name: "Company") }
        it { expect(company.association_cached?(:employee_without_bitemporals)).to eq false }
      end

      context "w/ eager_load" do
        let(:company) { Company.eager_load(:employee_without_bitemporals).find_by(name: "Company") }
        it { expect(company.association_cached?(:employee_without_bitemporals)).to eq true }
      end

    end

    context "#new to #save" do
      it do
        company = Company.new(name: "Company")
        company.employee_without_bitemporals.new(name: "Jane")
        company.employee_without_bitemporals.new(name: "Tom")
        expect(company.save).to eq true
      end
    end

    describe "#loaded?" do
      let(:company) { Company.create(name: "Jane") }
      before do
        company.employee_without_bitemporals.new(name: "Jane")
        company.employee_without_bitemporals.new(name: "Tom")
      end

      context "class association" do
        context "with `.eager_load`" do
          let(:employee_without_bitemporals) { Company.eager_load(:employee_without_bitemporals).find(company.id).association(:employee_without_bitemporals)  }
          it { expect(employee_without_bitemporals.loaded?).to eq true }
        end
      end
    end

    describe "inverse_of" do
      let(:company) do
        Class.new(Company) {
          has_many :employee_without_bitemporals, foreign_key: :company_id, inverse_of: :company

          def self.name
            "CompanyWithInverseOf"
          end
        }.create!(name: "Company")
      end
      before do
        company.update(name: "Company2")
        company.employee_without_bitemporals.create!(name: "Jane")
      end

      it { expect(company.reload.employee_without_bitemporals.first.company).to be company }
    end
  end

  describe "non BTDM has many BTDM" do
    let(:company) { CompanyWithoutBitemporal.create(name: "Company0").tap { |it| it.update(name: "Company1") } }

    before do
      # Dummy data
      CompanyWithoutBitemporal.create(name: "Dummy").tap { |company|
        company.employees.create(name: "Employee1")
        company.employees.create(name: "Employee2")
        company.employees.create(name: "Employee3")
      }
    end

    describe "#create" do
      subject { company.employees.create(name: "Employee1") }

      it { expect { subject }.to change(company.employees, :count).by(1) }
      it { expect { subject }.to change(company.employees, :first).from(nil).to(have_attributes name: "Employee1") }
      it { expect { subject }.to change { company.employees.ignore_valid_datetime.count }.by(1) }
      it { expect { subject }.to change { company.employees.find_by(name: "Employee1") }.from(nil).to(have_attributes name: "Employee1") }
    end

    describe "#update" do
      let!(:employee1) { company.employees.create(name: "Employee0").tap { |it| it.update(name: "Employee1") } }
      subject { employee1.update(name: "New") }

      it { expect { subject }.not_to change(company.employees, :count) }
      it { expect { subject }.to change { company.employees.first.reload.name }.to("New") }
      it { expect { subject }.to change { company.employees.ignore_valid_datetime.count }.by(1) }
    end

    describe "#force_update" do
      let!(:employee1) { company.employees.create(name: "Employee0").tap { |it| it.update(name: "Employee1") } }
      subject { employee1.force_update { |m| m.update(name: "New") } }

      it { expect { subject }.not_to change(company.employees, :count) }
      it { expect { subject }.to change { company.employees.first.reload.name }.to("New") }
      it { expect { subject }.to change { company.employees.ignore_valid_datetime.within_deleted.count }.by(1) }
    end

    describe "#destroy" do
      let!(:employee1) { company.employees.create(name: "Employee0").tap { |it| it.update(name: "Employee1") } }
      subject { employee1.destroy }

      it { expect { subject }.to change { company.employees.count }.by(-1) }
      it { expect { subject }.to change(employee1, :destroyed?).from(false).to(true) }
      it { expect { subject }.to change { company.employees.ignore_valid_datetime.within_deleted.count }.by(1) }
    end

    describe "relations" do
      let(:company2) { CompanyWithoutBitemporal.create(name: "Company1").tap { |it| it.update(name: "Company2") } }
      let!(:mado) { company.employees.create(name: "Mado") }
      let!(:tom) { company.employees.create(name: "Tom") }
      before do
        company.employees.create(name: "Tom").update(name: "Jane")
        @time = Time.current
        company.employees.create(name: "Mami").tap { |m|
          m.update(name: "Mado")
          m.update(name: "Homu")
        }
        company.employees.create(name: "Jane")

        company2.employees.create(name: "Jane")
        company2.employees.create(name: "Tom")
        company2.employees.create(name: "Mado")
      end

      describe ".find" do
        it { expect(company.employees.find(mado.id)).to have_attributes(name: "Mado") }
        it { expect(company.employees.find(mado.id, tom.id).pluck(:name)).to contain_exactly("Mado", "Tom") }
      end

      describe ".find_by" do
        it { expect(company.employees.find_by(name: "Mami")).to be_nil }
        it { expect(company.employees.find_by(name: "Mado")).to have_attributes(name: "Mado") }
        it { expect(company.employees.find_by(name: "Tom")).to have_attributes(name: "Tom") }
        it { expect(company.employees.find_by(name: "Jane")).to have_attributes(name: "Jane") }
      end

      describe ".where" do
        it { expect(company.employees.where(name: "Tom").count).to eq 1 }
        it { expect(company.employees.where(name: "Jane").count).to eq 2 }
        it { expect(company.employees.where(name: "Mado").count).to eq 1 }
        it { expect(company.employees.where(name: "Mami").count).to eq 0 }
        it do
          result = Employee.where(name: "Jane").pluck(:company_id, :bitemporal_id)
          expect(result).to contain_exactly(
            [company.id, company.employees.where(name: "Jane").first.id],
            [company.id, company.employees.where(name: "Jane").second.id],
            [company2.id, company2.employees.find_by(name: "Jane").id]
          )
        end
      end

      describe ".valid_at" do
        it { expect(Employee.valid_at(@time).count).to eq 6 }
        it { expect(company.employees.valid_at(@time).count).to eq 3 }
        it { expect(company2.employees.valid_at(@time).count).to eq 0 }
        it { expect(company.employees.valid_at(@time).where(name: "Jane").count).to eq 1 }
        it { expect(company.employees.valid_at(@time).where(name: "Tom").count).to eq 1 }
        it { expect(company.employees.valid_at(@time).where(name: "Homu").count).to eq 0 }
      end

      describe "preload" do
        before do
          CompanyWithoutBitemporal.create(name: "Company3")
        end
        it { expect(CompanyWithoutBitemporal.includes(:employees).all.count).to eq 4 }
        it { expect(CompanyWithoutBitemporal.joins(:employees).all.count).to eq 11 }
        it { expect(CompanyWithoutBitemporal.includes(:employees).where(employees: { name: "Jane" }).count).to eq 2 }
        it { expect(CompanyWithoutBitemporal.joins(:employees).where(employees: { name: "Jane" }).count).to eq 3 }
      end

      describe "#bitemporal_value" do
        it { expect(company.employees.bitemporal_value).to eq({ with_valid_datetime: :default_scope, with_transaction_datetime: :default_scope }) }
        it do
          relation = company.employees
          relation.bitemporal_value = { foo: :bar }
          expect(relation.bitemporal_value).to eq({ foo: :bar })
        end
      end
    end

    describe "nested_attributes" do
      context "with accepts_nested_attributes_for" do
        let(:company) {
          Class.new(CompanyWithoutBitemporal) {
            accepts_nested_attributes_for :employees
          }.create(name: "Company")
        }
        let!(:employee1) { company.employees.create(name: "Jane").tap { |m| m.update!(name: "Tom") } }
        let!(:employee2) { company.employees.create(name: "Homu").tap { |m| m.update!(name: "Mami") } }

        subject {
          company.employees_attributes = [
            { id: employee1.id, name: "Kevin" },
            { id: employee2.id, name: "Mado" }
          ]
          company.save
        }

        it { expect { subject }.not_to change { Employee.count } }
        it { expect { subject }.to change { Employee.ignore_valid_datetime.count }.by(2) }
        it { expect { subject }.to change { employee1.reload.name }.from("Tom").to("Kevin") }
        it { expect { subject }.to change { employee2.reload.name }.from("Mami").to("Mado") }
      end
    end

    describe "parent to destroyed" do
      context "has_many with `dependent: :nullify`" do
        let(:company) {
          class CompanyWithDependentNullify < CompanyWithoutBitemporal
            has_many :employees, dependent: :nullify, foreign_key: :company_id
          end
          CompanyWithDependentNullify.create(name: "Company")
        }
        let!(:employee1) { company.employees.create(name: "_").tap { |m| m.update(name: "Employee1") } }
        let!(:employee2) { company.employees.create(name: "_").tap { |m| m.update(name: "Employee2") } }

        subject { company.destroy }

        it { expect { subject }.to change { employee1.reload.company_id }.from(company.id).to(nil) }
        it { expect { subject }.to change { employee2.reload.company_id }.from(company.id).to(nil) }
      end
    end

    describe "inverse_of" do
      let(:company) do
        Class.new(CompanyWithoutBitemporal) {
          has_many :employees, foreign_key: :company_id, inverse_of: :company

          def self.name
            'CompanyWithInverseOf'
          end
        }.create!(name: "Company")
      end
      before do
        employee = company.employees.create!(name: "Jane")
        employee.update!(name: "Tom")
      end

      it { expect(company.reload.employees.first.company).to be company }
    end
  end

  describe "BTDM has many BTDM" do
    describe "nested_attributes" do
      context "with accepts_nested_attributes_for" do
        let(:company) {
          Class.new(Company) {
            accepts_nested_attributes_for :employees
          }.create(name: "Company")
        }
        let!(:employee1) { company.employees.create(name: "Jane").tap { |m| m.update(name: "Tom") } }
        let!(:employee2) { company.employees.create(name: "Homu").tap { |m| m.update(name: "Mami") } }

        subject {
          company.employees_attributes = [
            { id: employee1.id, name: "Kevin" },
            { id: employee2.id, name: "Mado" }
          ]
          company.save
        }

        it { expect { subject }.not_to change { Employee.count } }
        it { expect { subject }.to change { Employee.ignore_valid_datetime.count }.by(2) }
        it { expect { subject }.to change { employee1.reload.name }.from("Tom").to("Kevin") }
        it { expect { subject }.to change { employee2.reload.name }.from("Mami").to("Mado") }
      end
    end

    describe "sync valid_from in create" do
      let!(:employee1) { company.employees.new(name: "Jane") }
      let!(:employee2) { company.employees.new(name: "Homu") }
      let!(:employee3) { company.employees.new(name: "Mami", valid_from: "2016/01/15") }

      context "#new to #save" do
        let(:company) { Company.new(name: "Company") }

        context "saving" do
          subject { company.save }
          it { expect { subject }.to change { employee1.valid_from } }
          it { expect { subject }.to change { employee2.valid_from } }
          it { expect { subject }.not_to change { employee3.valid_from } }
        end

        context "saved" do
          subject { company.valid_from }
          before { company.save }
          it { is_expected.to eq employee1.valid_from }
          it { is_expected.to eq employee2.valid_from }
          it { expect(employee1.valid_from).to eq employee2.valid_from }
        end

        context "company with valid_from" do
          let(:company) { Company.new(name: "Company", valid_from: "2018/12/25") }
          subject { company.valid_from }
          before { company.save }

          it { is_expected.to eq "2018/12/25" }
          it { is_expected.to eq employee1.valid_from }
          it { is_expected.to eq employee2.valid_from }
          it { expect(employee1.valid_from).to eq employee2.valid_from }
        end

        context "nested associastion" do
          let(:valid_from) { "2019/1/1" }
          let!(:company) { Company.new(valid_from: valid_from) }
          let!(:employee) { company.employees.new }
          let!(:address) { employee.address = Address.new }
          before { company.save! }
          it { expect(company.valid_from).to eq valid_from }
          it { expect(employee.valid_from).to eq valid_from }
          it { expect(address.valid_from).to eq valid_from }

          context "address with `valid_from`" do
            let!(:address) { employee.address = Address.new(valid_from: "2010/1/1") }
            it { expect(address.valid_from).to eq "2010/1/1" }
          end
        end
      end

      context "#create to #save" do
        let(:company) { Company.create(name: "Company") }

        context "saving" do
          subject { company.save }
          it { expect { subject }.to change { employee1.valid_from } }
          it { expect { subject }.to change { employee2.valid_from } }
          it { expect { subject }.not_to change { employee3.valid_from } }
        end

        context "saved" do
          before { company.save }
          subject { company.valid_from }
          it { is_expected.not_to eq employee1.valid_from }
          it { is_expected.not_to eq employee2.valid_from }
          it { expect(employee1.valid_from).not_to eq employee2.valid_from }
        end
      end
    end

    describe "inverse_of" do
      let(:company) do
        Class.new(Company) {
          has_many :employees, foreign_key: :company_id, inverse_of: :company

          def self.name
            "CompanyWithInverseOf"
          end
        }.create!(name: "Company")
      end
      before do
        company.update!(name: "Company2")
        employee = company.employees.create!(name: "Jane")
        employee.update!(name: "Tom")
      end

      it { expect(company.reload.employees.first.company).to be company }
    end
  end

  describe "non BTDM has one BTDM" do
    describe "parent to destroyed" do
      context "has_one with `dependent: :nullify`" do
        let(:company) {
          class CompanyWithDependentNullify < CompanyWithoutBitemporal
            has_one :employee, dependent: :nullify, foreign_key: :company_id
          end
          CompanyWithDependentNullify.create(name: "Company")
        }
        let!(:employee) { Employee.create(name: "_", company_id: company.id).tap { |m| m.update(name: "Employee1") } }

        subject { company.destroy }

        it { expect { subject }.to change { employee.reload.company_id }.from(company.id).to(nil) }
      end
    end

    describe "inverse_of" do
      let(:employee) do
        Class.new(EmployeeWithoutBitemporal) {
          has_one :address, foreign_key: :employee_id, inverse_of: :employee

          def self.name
            "EmployeeWithInverseOf"
          end
        }.create!(name: "Jane")
      end
      before do
        address = employee.create_address!(city: "Tokyo")
        address.update!(city: "Osaka")
      end

      it { expect(employee.reload.address.employee).to be employee }
    end
  end

  describe "non BTDM has many non BTDM" do
    let(:company) { CompanyWithoutBitemporal.create(name: "Company") }
    describe "#loaded?" do
      before do
        company.employee_without_bitemporals.create(name: "Jane")
        company.employee_without_bitemporals.create(name: "Tom")
      end

      context "instance association" do
        let(:employees) { company.association(:employee_without_bitemporals) }
        it { expect { employees.reader.to_a }.to change(employees, :loaded?).from(false).to(true) }
      end

      context "class association" do
        context "with `.eager_load`" do
          let(:addresses) { CompanyWithoutBitemporal.eager_load(:employee_without_bitemporals).find(company.id).association(:employee_without_bitemporals)  }
          it { expect(addresses.loaded?).to eq true }
        end
      end
    end
  end

  describe "BTDM has one BTDM" do
    describe "inverse_of" do
      let(:employee) do
        Class.new(Employee) {
          has_one :address, foreign_key: :employee_id, inverse_of: :employee

          def self.name
            "EmployeeWithInverseOf"
          end
        }.create!(name: "Jane")
      end
      before do
        employee.update!(name: "Tom")
        employee.create_address!(city: "Tokyo")
          .update!(city: "Osaka") # create history
      end

      it { expect(employee.reload.address.employee).to be employee }
    end
  end
end
