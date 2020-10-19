# frozen_string_literal: true

require 'spec_helper'

# `polymorphic` options is
# https://guides.rubyonrails.org/association_basics.html#polymorphic-associations
ActiveRecord::Schema.define(version: 1) do
  create_table :pictures, force: true do |t|
    t.string :name
    t.integer :imageable_id
    t.string  :imageable_type
    t.index [:imageable_type, :imageable_id]
  end

  create_table :products, force: true do |t|
    t.string :name
    t.integer :bitemporal_id
    t.datetime :valid_from
    t.datetime :valid_to
    t.datetime :deleted_at

    t.timestamps
  end
end

class Picture < ActiveRecord::Base
  belongs_to :imageable, polymorphic: true
end

class Product < ActiveRecord::Base
  include ActiveRecord::Bitemporal

  has_many :pictures, as: :imageable
end

RSpec.describe "Model with polymorphic option" do
  context ".includes" do
    let(:product1) { Product.create!(name: "Product1") }
    let(:product2) { Product.create!(name: "Product2") }
    before do
      product1.pictures.create!(name: "Product1 Picture1")
      product1.pictures.create!(name: "Product1 Picture2")
      product2.pictures.create!(name: "Product2 Picture1")
      product2.pictures.create!(name: "Product2 Picture2")
    end
    subject { Picture.includes(:imageable) }
    it { is_expected.to have_attributes count: 4 }
  end

  context "with update" do
    let(:product) { Product.create!(name: "Product") }
    let(:picture1) { product.pictures.create(name: "Picture1") }
    let(:picture2) { product.pictures.create(name: "Picture2") }
    let(:picture1_imageable_name) { -> { picture1.imageable.name } }
    let(:picture2_imageable_name) { -> { picture2.imageable.name } }
    subject { -> { product.update!(name: "New") } }

    it { is_expected.to change(&picture1_imageable_name).from("Product").to("New") }
    it { is_expected.to change(&picture2_imageable_name).from("Product").to("New") }
  end
end
