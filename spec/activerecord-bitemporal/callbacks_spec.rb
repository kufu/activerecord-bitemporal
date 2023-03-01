# frozen_string_literal: true

require 'spec_helper'

ActiveRecord::Schema.define(version: 1) do
  create_table :job_titles, force: true do |t|
    t.string :name

    t.integer :employee_id

    t.integer :bitemporal_id
    t.datetime :valid_from
    t.datetime :valid_to
    t.datetime :deleted_at
    t.datetime :transaction_from
    t.datetime :transaction_to

    t.timestamps
  end
end

module BitemporalCallbacksLoggable
  extend ActiveSupport::Concern

  included do
    attr_accessor :log
    after_initialize { @log = [] }

    [:before_bitemporal_create, :after_bitemporal_create,
     :before_bitemporal_update, :after_bitemporal_update,
     :before_bitemporal_destroy, :after_bitemporal_destroy
    ].each do |callback_method|
      send(callback_method, Proc.new { |model| model.log << callback_method })
    end
  end

  def clear_log
    @log.clear
  end
end

class JobTitle < ActiveRecord::Base
  include ActiveRecord::Bitemporal
  include BitemporalCallbacksLoggable

  belongs_to :employee
end

class EmployeeWithBitemporalCallbacksLog < Employee
  include BitemporalCallbacksLoggable
  has_one :job_title, foreign_key: :employee_id, dependent: :destroy
  accepts_nested_attributes_for :job_title, allow_destroy: true
end

RSpec.describe ActiveRecord::Bitemporal::Callbacks do
  describe "bitemporal_create" do
    let(:employee) { EmployeeWithBitemporalCallbacksLog.new(name: "Jane") }
    subject { employee.save! }

    context 'without option `ignore_bitemporal_callbacks`' do
      it { expect { subject }.to change(employee, :log).from([]).to(%i[before_bitemporal_create after_bitemporal_create]) }
    end

    context 'with option `ignore_bitemporal_callbacks: false`' do
      before { employee.bitemporal_option_merge!(ignore_bitemporal_callbacks: false) }
      it { expect { subject }.to change(employee, :log).from([]).to(%i[before_bitemporal_create after_bitemporal_create]) }
    end

    context 'with option `ignore_bitemporal_callbacks: true`' do
      before { employee.bitemporal_option_merge!(ignore_bitemporal_callbacks: true) }
      it { expect { subject }.not_to change(employee, :log) }
    end

    context 'with nested_attributes' do
      before { employee.build_job_title(name: "CEO") }
      it { expect { subject }.to change(employee, :log).from([]).to(%i[before_bitemporal_create after_bitemporal_create]) }
      it { expect { subject }.to change { employee.job_title.log }.from([]).to(%i[before_bitemporal_create after_bitemporal_create]) }
    end
  end

  describe "bitemporal_update" do
    let(:employee) { EmployeeWithBitemporalCallbacksLog.create!(name: "Jane").tap(&:clear_log) }
    subject { employee.update!(name: "Tom") }

    context 'without option `ignore_bitemporal_callbacks`' do
      it { expect { subject }.to change(employee, :log).from([]).to(%i[before_bitemporal_update after_bitemporal_update]) }
    end

    context 'with option `ignore_bitemporal_callbacks: false`' do
      before { employee.bitemporal_option_merge!(ignore_bitemporal_callbacks: false) }
      it { expect { subject }.to change(employee, :log).from([]).to(%i[before_bitemporal_update after_bitemporal_update]) }
    end

    context 'with option `ignore_bitemporal_callbacks: true`' do
      before { employee.bitemporal_option_merge!(ignore_bitemporal_callbacks: true) }
      it { expect { subject }.not_to change(employee, :log) }
    end

    context 'with nested_attributes' do
      let(:employee) {
        EmployeeWithBitemporalCallbacksLog.create!(name: "Jane").tap { |e|
          e.create_job_title!(name: "CEO").tap(&:clear_log)
          e.clear_log
        }
      }
      subject {
        employee.assign_attributes(**update_attributes)
        employee.save!
      }

      context 'employee and job_title have changes' do
        let(:update_attributes) { { name: "Tom", job_title_attributes: { id: employee.job_title.id, name: "COO" } } }
        it { expect { subject }.to change(employee, :log).from([]).to(%i[before_bitemporal_update after_bitemporal_update]) }
        it { expect { subject }.to change { employee.job_title.log }.from([]).to(%i[before_bitemporal_update after_bitemporal_update]) }
      end

      context 'employee has changes and job_title does not have changes' do
        let(:update_attributes) { { name: "Tom" } }
        it { expect { subject }.to change(employee, :log).from([]).to(%i[before_bitemporal_update after_bitemporal_update]) }
        it { expect { subject }.not_to change { employee.job_title.log } }
      end

      context 'employee does not have changes and job_title has changes' do
        let(:update_attributes) { { job_title_attributes: { id: employee.job_title.id, name: "COO" } } }
        it { expect { subject }.to change(employee, :log).from([]).to(%i[before_bitemporal_update after_bitemporal_update]) }
        it { expect { subject }.to change { employee.job_title.log }.from([]).to(%i[before_bitemporal_update after_bitemporal_update]) }
      end
    end
  end

  describe "bitemporal_destroy" do
    let(:employee) { EmployeeWithBitemporalCallbacksLog.create!(name: "Jane").tap(&:clear_log) }
    subject { employee.destroy! }

    context 'without option `ignore_bitemporal_callbacks`' do
      it { expect { subject }.to change(employee, :log).from([]).to(%i[before_bitemporal_destroy after_bitemporal_destroy]) }
    end

    context 'with option `ignore_bitemporal_callbacks: false`' do
      before { employee.bitemporal_option_merge!(ignore_bitemporal_callbacks: false) }
      it { expect { subject }.to change(employee, :log).from([]).to(%i[before_bitemporal_destroy after_bitemporal_destroy]) }
    end

    context 'with option `ignore_bitemporal_callbacks: true`' do
      before { employee.bitemporal_option_merge!(ignore_bitemporal_callbacks: true) }
      it { expect { subject }.not_to change(employee, :log) }
    end

    context 'has_one relation' do
      let(:employee) {
        EmployeeWithBitemporalCallbacksLog.create!(name: "Jane").tap { |e|
          e.create_job_title!(name: "CEO").tap(&:clear_log)
          e.clear_log
        }
      }

      context 'with `dependent: :destroy`' do
        subject { employee.destroy! }
        it { expect { subject }.to change(employee, :log).from([]).to(%i[before_bitemporal_destroy after_bitemporal_destroy]) }
        it { expect { subject }.to change { employee.job_title.log }.from([]).to(%i[before_bitemporal_destroy after_bitemporal_destroy]) }
      end

      context 'with nested_attributes' do
        subject {
          employee.assign_attributes({ job_title_attributes: { id: employee.job_title.id, _destroy: true } })
          employee.save!
        }
        it { expect { subject }.to change { employee.job_title.log }.from([]).to(%i[before_bitemporal_destroy after_bitemporal_destroy]) }
      end
    end
  end
end
