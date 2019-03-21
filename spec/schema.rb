ActiveRecord::Schema.define(version: 1) do
  create_table :companies, force: true do |t|
    t.string :name

    t.integer :bitemporal_id
    t.datetime :valid_from
    t.datetime :valid_to
    t.datetime :deleted_at

    t.timestamps
  end

  create_table :company_without_bitemporals, force: true do |t|
    t.string :name

    t.timestamps
  end

  create_table :employees, force: true do |t|
    t.string :name
    t.string :emp_code
    t.datetime :archived_at

    t.integer :company_id
    t.integer :companies_id

    t.integer :bitemporal_id
    t.datetime :valid_from
    t.datetime :valid_to
    t.datetime :deleted_at

    t.timestamps
  end

  create_table :employee_without_bitemporals, force: true do |t|
    t.string :name
    t.string :emp_code
    t.datetime :archived_at

    t.integer :company_id

    t.timestamps
  end

  create_table :addresses, force: true do |t|
    t.integer :employee_id

    t.string :city
    t.string :name

    t.integer :bitemporal_id
    t.datetime :valid_from
    t.datetime :valid_to
    t.datetime :deleted_at

    t.timestamps
  end

  create_table :address_without_bitemporals, force: true do |t|
    t.integer :employee_id

    t.string :city

    t.timestamps
  end
end

class Company < ActiveRecord::Base
  include ActiveRecord::Bitemporal

  has_many :employees, foreign_key: :company_id
  has_many :employee_without_bitemporals, foreign_key: :company_id
end

class CompanyWithoutBitemporal < ActiveRecord::Base
  has_many :employees, foreign_key: :company_id
  has_many :employee_without_bitemporals, foreign_key: :company_id
end


class Employee < ActiveRecord::Base
  include ActiveRecord::Bitemporal

  belongs_to :company, foreign_key: :company_id

  has_one  :address,   foreign_key: :employee_id
  has_one  :address_without_bitemporal,  foreign_key: :employee_id

  class <<self
    attr_accessor :call_after_save_count
    attr_accessor :call_before_destroy_count
    attr_accessor :call_after_destroy_count
  end
  Employee.call_after_save_count = 0
  Employee.call_before_destroy_count = 0
  Employee.call_after_destroy_count = 0

  after_save :on_after_save
  def on_after_save
    Employee.call_after_save_count += 1
  end

  before_destroy :on_before_destroy
  def on_before_destroy
    Employee.call_before_destroy_count += 1
  end

  after_destroy :on_after_destroy
  def on_after_destroy
    Employee.call_after_destroy_count += 1
  end
end

class EmployeeWithoutBitemporal < ActiveRecord::Base
  belongs_to :company, foreign_key: :company_id

  has_one  :address,   foreign_key: :employee_id
  has_one  :address_without_bitemporal,  foreign_key: :employee_id
end


class Address < ActiveRecord::Base
  include ActiveRecord::Bitemporal

  belongs_to :employee, foreign_key: :employee_id
end

class AddressWithoutBitemporal < ActiveRecord::Base
  belongs_to :employee, foreign_key: :employee_id
end

