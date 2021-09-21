# frozen_string_literal: true

require 'spec_helper'


ActiveRecord::Schema.define(version: 1) do
  create_table :blogs, force: true do |t|
    t.string :name

    t.integer :bitemporal_id
    t.datetime :valid_from
    t.datetime :valid_to
    t.datetime :deleted_at
    t.datetime :transaction_from
    t.datetime :transaction_to

    t.timestamps
  end

  create_table :users, force: true do |t|
    t.string :name

    t.integer :bitemporal_id
    t.datetime :valid_from
    t.datetime :valid_to
    t.datetime :deleted_at
    t.datetime :transaction_from
    t.datetime :transaction_to

    t.timestamps
  end

  create_table :articles, force: true do |t|
    t.string :title

    t.integer :user_id
    t.integer :blog_id

    t.integer :bitemporal_id
    t.datetime :valid_from
    t.datetime :valid_to
    t.datetime :deleted_at
    t.datetime :transaction_from
    t.datetime :transaction_to

    t.timestamps
  end

  create_table :comments, force: true do |t|
    t.string :body

    t.integer :article_id

    t.timestamps
  end
end

class Blog < ActiveRecord::Base
  include ActiveRecord::Bitemporal
  has_many :articles
  has_many :users, through: :articles
  has_many :comments, through: :articles
end

class User < ActiveRecord::Base
  include ActiveRecord::Bitemporal
  has_many :articles
end

class Article < ActiveRecord::Base
  include ActiveRecord::Bitemporal
  belongs_to :blog
  belongs_to :user
  has_many :comments
end

class Comment < ActiveRecord::Base
  belongs_to :article
end

RSpec.describe "has_xxx with through" do
  describe "created" do
    let!(:blog) { Blog.create!(name: "tabelog").tap { |it| it.update(name: "sushilog") } }
    let!(:user) { User.create!(name: "Jane").tap { |it| it.update(name: "Tom") } }
    let!(:article) { user.articles.create!(title: "yakiniku", blog: blog).tap { |it| it.update(title: "sushi") } }
    let!(:comment) { article.comments.create!(body: "nice") }

    it { expect(blog.users.count).to eq 1 }
    it { expect(blog.articles.count).to eq 1 }
    it { expect(user.articles.count).to eq 1 }
    it { expect(blog.comments.count).to eq 1 }
    it { expect(article.blog).to eq blog }
    it { expect(article.user).to eq user }

    context "user.create" do
      subject { -> { blog.users.create!(name: "Homu") } }
      it { is_expected.to change { blog.users.count }.by(1) }
      it { is_expected.to change { blog.articles.count }.by(1) }
      it { is_expected.not_to change { user.articles.count } }
    end

    context "user.articles.create" do
      subject { -> { user.articles.create!(title: "sukiyaki", blog: blog) } }
      it { is_expected.to change { blog.users.count }.by(1) }
      it { is_expected.to change { blog.articles.count }.by(1) }
      it { is_expected.to change { user.articles.count }.by(1) }
    end
  end

  describe "updated" do
    let!(:blog) { Blog.create!(name: "tabelog").tap { |it| it.update(name: "sushilog") } }
    let!(:user) { User.create!(name: "Jane").tap { |it| it.update(name: "Tom") } }
    let!(:article) { user.articles.create!(title: "yakiniku", blog: blog).tap { |it| it.update(title: "sushi") } }

    context "user.update" do
      subject { -> { user.update(name: "Kevin") } }
      it { is_expected.not_to change { blog.users.count } }
      it { is_expected.not_to change { blog.articles.count } }
      it { is_expected.not_to change { user.articles.count } }
      it { is_expected.to change { blog.users.first.name }.from("Tom").to("Kevin") }

      it { is_expected.to change { blog.users.ignore_valid_datetime.count }.by(2) }
      it { is_expected.not_to change { blog.articles.ignore_valid_datetime.count } }
    end

    context "article.update" do
      subject { -> { article.update(title: "kaisendon") } }
      it { is_expected.not_to change { blog.users.count } }
      it { is_expected.not_to change { blog.articles.count } }
      it { is_expected.not_to change { user.articles.count } }
      it { is_expected.to change { blog.articles.first.title }.from("sushi").to("kaisendon") }
      it { is_expected.to change { user.articles.first.title }.from("sushi").to("kaisendon") }

      it { is_expected.to change { blog.users.ignore_valid_datetime.count }.by(2) }
      it { is_expected.to change { blog.articles.ignore_valid_datetime.count }.by(1) }
    end
  end

  describe "with valid_at" do
    let(:blog) { Blog.create!(name: "tabelog") }
    let(:user) { User.create!(name: "Jane") }
    let(:article) { user.articles.create!(title: "yakiniku", blog: blog) }
    let(:transaction_from) { "2017/5/1" }
    let(:updated_at) { "2017/10/1" }

    before do
      Timecop.freeze(transaction_from) { blog; user; article }
    end

    context "user.update" do
      before { Timecop.freeze(updated_at) { user.update(name: "Tom") } }
      it { expect(blog.users.valid_at(transaction_from).first.name).to eq "Jane" }
      it { expect(blog.users.valid_at(updated_at).first.name).to eq "Tom" }

      it { expect(Blog.find_at_time(transaction_from, blog.id).users.first.name).to eq "Jane" }
      it { expect(Blog.find_at_time(updated_at, blog.id).users.first.name).to eq "Tom" }

      it { expect(blog.valid_at(transaction_from) { |m| m.users.first.name }).to eq "Jane" }
      it { expect(blog.valid_at(updated_at) { |m| m.users.first.name }).to eq "Tom" }
    end

    context "article.update" do
      before { Timecop.freeze(updated_at) { article.update(title: "sushi") } }
      it { expect(blog.users.valid_at(transaction_from).first.articles.first.title).to eq "yakiniku" }
      it { expect(blog.users.valid_at(updated_at).first.articles.first.title).to eq "sushi" }

      it { expect(blog.users.first.articles.valid_at(transaction_from).first.title).to eq "yakiniku" }
      it { expect(blog.users.first.articles.valid_at(updated_at).first.title).to eq "sushi" }

      it { expect(Blog.find_at_time(transaction_from, blog.id).users.first.articles.first.title).to eq "yakiniku" }
      it { expect(Blog.find_at_time(updated_at, blog.id).users.first.articles.first.title).to eq "sushi" }
    end

    context "update article for association user" do
      let(:user2) { User.create!(name: "Tom") }
      before { Timecop.freeze(updated_at) { article.update(user: user2) } }

      it { expect(blog.users.valid_at(transaction_from).first.name).to eq "Jane" }
      it { expect(blog.users.valid_at(updated_at).first.name).to eq "Tom" }

      it { expect(Blog.find_at_time(transaction_from, blog.id).users.first.name).to eq "Jane" }
      it { expect(Blog.find_at_time(updated_at, blog.id).users.first.name).to eq "Tom" }

      it { expect(blog.valid_at(transaction_from) { |m| m.users.first.name }).to eq "Jane" }
      it { expect(blog.valid_at(updated_at) { |m| m.users.first.name }).to eq "Tom" }

      it { expect(blog.users.find_at_time(transaction_from, user.id).name).to eq "Jane" }
      it { expect(blog.users.find_at_time(updated_at, user.id)).to be_nil }

      it { expect(blog.users.find_at_time(transaction_from, user2.id)).to be_nil }
      it { expect(blog.users.find_at_time(updated_at, user2.id).name).to eq "Tom" }
    end
  end

  describe ".to_sql" do
    let(:blog) { Blog.create!(name: "tabelog") }
    let(:user) { User.create!(name: "Jane") }
    let(:article) { user.articles.create!(title: "yakiniku", blog: blog) }
    let(:relation) { nil }
    let(:relation_time) { "2019/1/1" }
    subject { Timecop.freeze(relation_time) { relation.to_sql } }
    before do
      @old_time_zone = Time.zone
      Time.zone = "Tokyo"
    end
    after { Time.zone = @old_time_zone }

    describe "default scope" do
      let(:relation) { blog.users }
      it { is_expected.to match %r/articles"."valid_from" <= '2018-12-31 15:00:00' AND "articles"."valid_to" > '2018-12-31 15:00:00'/ }
      it { is_expected.to match %r/"users"."valid_from" <= '2018-12-31 15:00:00' AND "users"."valid_to" > '2018-12-31 15:00:00'/ }
    end

    context "with valid_at" do
      let(:relation) { blog.users.valid_at("2019/2/2") }
      it { is_expected.to match %r/"users"."valid_from" <= '2019-02-01 15:00:00' AND "articles"."valid_from" <= '2019-02-01 15:00:00'/ }
      it { is_expected.to match %r/"users"."valid_to" > '2019-02-01 15:00:00' AND "articles"."valid_to" > '2019-02-01 15:00:00'/ }
      it { is_expected.to match %r/"users"."valid_from" <= '2019-02-01 15:00:00' AND "articles"."valid_from" <= '2019-02-01 15:00:00' AND "users"."valid_to" > '2019-02-01 15:00:00' AND "articles"."valid_to" > '2019-02-01 15:00:00'/ }
    end

    context "with ignore_valid_datetime" do
      let(:relation) { blog.users.ignore_valid_datetime }
      it do
        is_expected.not_to match(/articles"."valid_from" <= '2018-12-31 15:00:00' AND "articles"."valid_to" > '2018-12-31 15:00:00'/)
        is_expected.not_to match(/"users"."valid_from" <= '2018-12-31 15:00:00' AND "users"."valid_to" > '2018-12-31 15:00:00'/)
      end
    end
  end
end
