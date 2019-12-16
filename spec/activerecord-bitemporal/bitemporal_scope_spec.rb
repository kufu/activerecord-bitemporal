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
end

class Blog < ActiveRecord::Base
  include ActiveRecord::Bitemporal
  has_many :articles
  has_many :users, through: :articles
end

class User < ActiveRecord::Base
  include ActiveRecord::Bitemporal
  has_many :articles
end

class Article < ActiveRecord::Base
  include ActiveRecord::Bitemporal
  belongs_to :blog
  belongs_to :user
end


RSpec.describe ActiveRecord::Bitemporal::Scope do
  describe "bitemporal_scope" do
    let(:time_current) { Time.current.round }
    let(:sql) { Timecop.freeze(time_current) { relation.to_sql } }
    define_method(:scan_once) { |x| satisfy { |sql| sql.scan(x).one? } }
    RSpec::Matchers.define_negated_matcher :not_scan, :scan_once

    define_method(:have_valid_at) { |datetime = Time.current, table:|
           scan_once(%{"#{table}"."valid_from"})
      .and scan_once(%{"#{table}"."valid_to"})
      .and include(%{"#{table}"."valid_from" <= '#{datetime.to_s(:db)}'})
      .and include(%{"#{table}"."valid_to" > '#{datetime.to_s(:db)}'})
    }
    define_method(:not_have_valid_at) { |table:|
           not_scan(%{"#{table}"."valid_from"})
      .and not_scan(%{"#{table}"."valid_to"})
    }
    define_method(:have_transaction_at) { |datetime, table:|
           scan_once(%{"#{table}"."transaction_from"})
      .and scan_once(%{"#{table}"."transaction_to"})
      .and include(%{"#{table}"."transaction_from" <= '#{datetime.to_s(:db)}'})
      .and include(%{"#{table}"."transaction_to" > '#{datetime.to_s(:db)}'})
    }
    define_method(:not_have_transaction_at) { |table:|
           not_scan(%{"#{table}"."transaction_from"})
      .and not_scan(%{"#{table}"."transaction_to"})
    }
    define_method(:have_bitemporal_at) { |datetime, table:|
      have_valid_at(datetime, table: table).and have_transaction_at(datetime, table: table)
    }
    define_method(:not_have_bitemporal_at) { |table:|
      not_have_valid_at(table: table).and not_have_transaction_at(table: table)
    }

    subject { Timecop.freeze(time_current) { sql } }

    describe "default_scope" do
      let(:relation) { User.all }
      it { is_expected.to have_bitemporal_at(time_current, table: "users") }
    end

    describe ".ignore_valid_datetime" do
      let(:relation) { User.ignore_valid_datetime }
      it { is_expected.to not_have_valid_at(table: "users") }
      it { is_expected.to have_transaction_at(time_current, table: "users") }

      describe ".valid_at" do
        let(:valid_datetime) { "2019/01/01".in_time_zone }
        let(:relation) { User.ignore_valid_datetime.valid_at(valid_datetime) }
        it { is_expected.to have_valid_at(valid_datetime, table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "users") }
      end
    end

    describe ".ignore_transaction_datetime" do
      let(:relation) { User.ignore_transaction_datetime }
      it { is_expected.to have_valid_at(time_current, table: "users") }
      it { is_expected.to not_have_transaction_at(table: "users") }

      describe ".transaction_at" do
        let(:transaction_datetime) { "2019/01/01".in_time_zone }
        let(:relation) { User.ignore_transaction_datetime.transaction_at(transaction_datetime) }
        it { is_expected.to have_valid_at(time_current, table: "users") }
        it { is_expected.to have_transaction_at(transaction_datetime, table: "users") }
      end
    end

    describe ".ignore_bitemporal_datetime" do
      let(:relation) { User.ignore_bitemporal_datetime }
      it { is_expected.to not_have_bitemporal_at(table: "users") }

      describe ".valid_at" do
        let(:valid_datetime) { "2019/01/01".in_time_zone }
        let(:relation) { User.ignore_valid_datetime.valid_at(valid_datetime) }
        it { is_expected.to have_valid_at(valid_datetime, table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "users") }
      end

      describe ".transaction_at" do
        let(:transaction_datetime) { "2019/01/01".in_time_zone }
        let(:relation) { User.ignore_transaction_datetime.transaction_at(transaction_datetime) }
        it { is_expected.to have_valid_at(time_current, table: "users") }
        it { is_expected.to have_transaction_at(transaction_datetime, table: "users") }
      end
    end

    describe ".valid_at" do
      let(:valid_datetime) { "2019/01/01".in_time_zone }
      let(:relation) { User.valid_at(valid_datetime) }
      it { is_expected.to have_valid_at(valid_datetime, table: "users") }
      it { is_expected.to have_transaction_at(time_current, table: "users") }

      context "valid_datetime is nil" do
        let(:valid_datetime) { nil }
        it { is_expected.to have_bitemporal_at(time_current, table: "users") }
      end

      describe ".valid_at" do
        let(:valid_datetime) { "2019/01/01".in_time_zone }
        let(:relation) { User.valid_at("2019/05/01").valid_at(valid_datetime) }
        it { is_expected.to have_valid_at(valid_datetime, table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "users") }
      end

      describe ".ignore_valid_datetime" do
        let(:relation) { User.valid_at("2019/01/01").ignore_valid_datetime }
        it { is_expected.to not_have_valid_at(table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "users") }
      end
    end

    describe ".transaction_at" do
      let(:transaction_datetime) { "2019/01/01".in_time_zone }
      let(:relation) { User.transaction_at(transaction_datetime) }
      it { is_expected.to have_valid_at(time_current, table: "users") }
      it { is_expected.to have_transaction_at(transaction_datetime, table: "users") }

      context "transaction_datetime is nil" do
        let(:transaction_datetime) { nil }
        it { is_expected.to have_bitemporal_at(time_current, table: "users") }
      end
    end

    describe ".bitemporal_at" do
      let(:bitemporal_datetime) { "2019/01/01".in_time_zone }
      let(:relation) { User.bitemporal_at(bitemporal_datetime) }
      it { is_expected.to have_bitemporal_at(bitemporal_datetime, table: "users") }

      context "bitemporal_datetime is nil" do
        let(:bitemporal_datetime) { nil }
        it { is_expected.to have_bitemporal_at(time_current, table: "users") }
      end

      context "duplicates" do
        let(:bitemporal_datetime) { "2019/01/01".in_time_zone }
        let(:relation) { User.bitemporal_at("2019/05/05").bitemporal_at(bitemporal_datetime) }
        it { is_expected.to have_bitemporal_at(bitemporal_datetime, table: "users") }
      end
    end

    context "duplicates `valid_from_lt" do
      let(:relation) { User.valid_from_lt("2019/01/01").valid_from_lt("2019/03/03") }
      it { is_expected.to scan_once("valid_from").and scan_once("valid_to") }
      it { is_expected.to include %{"valid_from" < '2019-03-03 00:00:00'} }
      it { is_expected.to include %{"valid_to" > '#{time_current.to_s(:db)}'} }
      it { is_expected.to have_transaction_at(time_current, table: "users") }
    end

    context "duplicates `valid_from_lt` and `valid_from_lteq`" do
      let(:relation) { User.valid_from_lt("2019/01/01").valid_from_lteq("2019/03/03") }
      it { is_expected.to scan_once("valid_from").and scan_once("valid_to") }
      it { is_expected.to include %{"valid_from" <= '2019-03-03 00:00:00'} }
      it { is_expected.to include %{"valid_to" > '#{time_current.to_s(:db)}'} }
      it { is_expected.to have_transaction_at(time_current, table: "users") }
    end

    describe ".merge" do
      context "with valid_at" do
        let(:valid_datetime) { "2019/01/01".in_time_zone }
        let(:relation) { User.merge(User.valid_at(valid_datetime)) }
        it { is_expected.to have_valid_at(valid_datetime, table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "users") }
      end

      context "overwrite valid_at when before" do
        let(:valid_datetime) { "2019/01/01".in_time_zone }
        let(:relation) { User.valid_at("2019/09/01").merge(User.valid_at(valid_datetime)) }
        it { is_expected.to have_valid_at(valid_datetime, table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "users") }
      end

      context "overwrite valid_at when after" do
        let(:valid_datetime) { "2019/01/01".in_time_zone }
        let(:relation) { User.merge(User.valid_at("2019/09/01")).valid_at(valid_datetime) }
        it { is_expected.to have_valid_at(valid_datetime, table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "users") }
      end

      context "with ignore_valid_datetime" do
        let(:relation) { User.merge(User.ignore_valid_datetime) }
        it { is_expected.to not_have_valid_at(table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "users") }
      end
    end

    describe "ActiveRecord::Bitemporal.valid_at" do
      let(:valid_datetime) { "2019/05/05".in_time_zone }
      let(:relation) { ActiveRecord::Bitemporal.valid_at(valid_datetime) { User.all } }
      it { is_expected.to have_valid_at(valid_datetime, table: "users") }
      it { is_expected.to have_transaction_at(time_current, table: "users") }

      context "valid_datetime is nil" do
        let(:valid_datetime) { nil }
        it { is_expected.to have_bitemporal_at(time_current, table: "users") }
      end

      describe ".valid_at" do
        let(:user_valid_datetime) { "2019/05/05".in_time_zone }
        let(:relation) { ActiveRecord::Bitemporal.valid_at(valid_datetime) { User.valid_at(user_valid_datetime) } }
        it { is_expected.to have_valid_at(user_valid_datetime, table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "users") }
      end

      context "with ActiveRecord::Bitemporal.ignore_valid_datetime" do
        let(:relation) { ActiveRecord::Bitemporal.valid_at(valid_datetime) { ActiveRecord::Bitemporal.ignore_valid_datetime { User.all } } }
        it { is_expected.to not_have_valid_at(table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "users") }
      end

      context ".ignore_valid_datetime" do
        let(:relation) { ActiveRecord::Bitemporal.valid_at(valid_datetime) { User.ignore_valid_datetime } }
        it { is_expected.to not_have_valid_at(table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "users") }
      end

      describe "ActiveRecord::Bitemporal.valid_at!" do
        let(:valid_datetime2) { "2019/06/06".in_time_zone }
        let(:relation) { ActiveRecord::Bitemporal.valid_at(valid_datetime) { ActiveRecord::Bitemporal.valid_at(valid_datetime2) { User.all } } }
        it { is_expected.to have_valid_at(valid_datetime2, table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "users") }
      end
    end

    describe "ActiveRecord::Bitemporal.valid_at!" do
      let(:valid_datetime) { "2019/05/05".in_time_zone }
      let(:relation) { ActiveRecord::Bitemporal.valid_at!(valid_datetime) { User.all } }
      it { is_expected.to have_valid_at(valid_datetime, table: "users") }
      it { is_expected.to have_transaction_at(time_current, table: "users") }

      context "valid_datetime is nil" do
        let(:valid_datetime) { nil }
        it { is_expected.to have_bitemporal_at(time_current, table: "users") }

        context "with .valid_at" do
          it { is_expected.to have_bitemporal_at(time_current, table: "users") }
        end
      end

      describe ".valid_at" do
        let(:user_valid_datetime) { "2019/05/05".in_time_zone }
        let(:relation) { ActiveRecord::Bitemporal.valid_at!(valid_datetime) { User.valid_at(user_valid_datetime) } }
        it { is_expected.to have_valid_at(valid_datetime, table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "users") }
      end

      context ".ignore_valid_datetime" do
        let(:relation) { ActiveRecord::Bitemporal.valid_at!(valid_datetime) { User.ignore_valid_datetime } }
        it { is_expected.to not_have_valid_at(table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "users") }
      end
    end

    describe "ActiveRecord::Bitemporal.ignore_valid_datetime" do
      let(:relation) { ActiveRecord::Bitemporal.ignore_valid_datetime { User.all } }
      it { is_expected.to not_have_valid_at(table: "users") }
      it { is_expected.to have_transaction_at(time_current, table: "users") }

      context "with ActiveRecord::Bitemporal.valid_at" do
        let(:valid_datetime) { "2019/05/05".in_time_zone }
        let(:relation) { ActiveRecord::Bitemporal.ignore_valid_datetime { ActiveRecord::Bitemporal.valid_at(valid_datetime) { User.all } } }
        it { is_expected.to have_valid_at(valid_datetime, table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "users") }
      end

      context "with .valid_at" do
        let(:valid_datetime) { "2019/05/05".in_time_zone }
        let(:relation) { ActiveRecord::Bitemporal.ignore_valid_datetime { User.valid_at(valid_datetime) } }
        it { is_expected.to have_valid_at(valid_datetime, table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "users") }
      end
    end

    describe ".unscoped" do
      let(:relation) { User.unscoped { User.all } }
      it { is_expected.not_to scan_once("valid_from") }
      it { is_expected.not_to scan_once("valid_to") }
      it { is_expected.not_to scan_once("transaction_from") }
      it { is_expected.not_to scan_once("transaction_to") }
    end

    describe ".scoping" do
      let(:valid_datetime) { "2019/01/01".in_time_zone }
      let(:relation) { User.valid_at(valid_datetime).scoping { User.all } }
      it { is_expected.to have_valid_at(valid_datetime, table: "users") }
      it { is_expected.to have_transaction_at(time_current, table: "users") }
    end

    describe "association" do
      let(:relation) { Blog.all }

      it { is_expected.to have_bitemporal_at(time_current, table: "blogs") }
      it { is_expected.to not_have_bitemporal_at(table: "articles") }

      describe ".joins" do
        let(:relation) { Blog.joins(:articles) }
        it { is_expected.to have_bitemporal_at(time_current, table: "blogs") }
        it { is_expected.to have_bitemporal_at(time_current, table: "articles") }

        # Not suppoted call to_sql outside unscoped
        xcontext "with call to_sql outside `Article.unscoped`" do
          let(:sql) { Article.unscoped { Blog.joins(:articles) }.to_sql }
          it { is_expected.to have_bitemporal_at(time_current, table: "blogs") }
          it { is_expected.to not_have_bitemporal_at(table: "articles") }
        end

        context "with call to_sql in `Article.unscoped`" do
          let(:sql) { Article.unscoped { Blog.joins(:articles).to_sql } }
          it { is_expected.to have_bitemporal_at(time_current, table: "blogs") }
          it { is_expected.to not_have_bitemporal_at(table: "articles") }
        end

        context "with call to_sql in `ActiveRecord::Bitemporal.valid_at`" do
          let(:valid_datetime) { "2019/01/01".in_time_zone }
          let(:sql) { ActiveRecord::Bitemporal.valid_at(valid_datetime) { Blog.joins(:articles).to_sql } }
          it { is_expected.to have_valid_at(valid_datetime, table: "blogs") }
          it { is_expected.to have_transaction_at(time_current, table: "blogs") }
          it { is_expected.to have_valid_at(valid_datetime, table: "articles") }
          it { is_expected.to have_transaction_at(time_current, table: "articles") }
        end

        describe ".merge" do
          context "with Article's relation in `Article.unscoped`" do
            let(:sql) { Article.unscoped { Blog.joins(:articles).merge(Article.valid_at("2019/01/01")).to_sql } }
            it { is_expected.to have_bitemporal_at(time_current, table: "blogs") }
            it { is_expected.to have_valid_at("2019/01/01".in_time_zone, table: "articles") }
            # Not suppoted merge
            # `Article.valid_at("2019/01/01")` without `default_scope` in `Article.unscoped`
            xit { is_expected.to have_transaction_at(time_current, table: "articles") }

            context "with bitemporal_default_scope" do
              let(:sql) { Article.unscoped { Blog.joins(:articles).merge(Article.bitemporal_default_scope.valid_at("2019/01/01")).to_sql } }
              it { is_expected.to have_bitemporal_at(time_current, table: "blogs") }
              it { is_expected.to have_valid_at("2019/01/01".in_time_zone, table: "articles") }
              # OK
              it { is_expected.to have_transaction_at(time_current, table: "articles") }
            end
          end

          context "without Article.unscoped" do
            let(:relation) { Blog.joins(:articles).merge(Article.valid_at("2019/01/01")) }

            it { is_expected.to have_bitemporal_at(time_current, table: "blogs") }
            # Not suppoted merge
            # Duplecated Article default_scope
            xit { is_expected.to have_valid_at("2019/01/01".in_time_zone, table: "articles") }
            xit { is_expected.to have_transaction_at(time_current, table: "articles") }
          end
        end

        describe ".left_joins" do
          let(:relation) { Blog.joins(:articles).left_joins(:articles) }

          it { is_expected.to have_valid_at(time_current, table: "blogs") }
          it { is_expected.to have_valid_at(time_current, table: "articles") }
          it { is_expected.to have_valid_at(time_current, table: "articles_blogs") }

          it { is_expected.to have_transaction_at(time_current, table: "blogs") }
          it { is_expected.to have_transaction_at(time_current, table: "articles") }
          it { is_expected.to have_transaction_at(time_current, table: "articles_blogs") }

          context "with call to_sql in `ActiveRecord::Bitemporal.valid_at`" do
            let(:valid_datetime) { "2019/01/01".in_time_zone }
            let(:sql) { ActiveRecord::Bitemporal.valid_at(valid_datetime) { relation.to_sql } }

            it { is_expected.to have_valid_at(valid_datetime, table: "blogs") }
            it { is_expected.to have_valid_at(valid_datetime, table: "articles") }
            it { is_expected.to have_valid_at(valid_datetime, table: "articles_blogs") }

            it { is_expected.to have_transaction_at(time_current, table: "blogs") }
            it { is_expected.to have_transaction_at(time_current, table: "articles") }
            it { is_expected.to have_transaction_at(time_current, table: "articles_blogs") }
          end
        end
      end

      describe "call has_many associations" do
        let(:relation) { Blog.create.articles }
        it { is_expected.to have_bitemporal_at(time_current, table: "articles") }

        context "with .valid_at" do
          let(:valid_datetime) { "2019/01/01".in_time_zone }
          let(:relation) { Blog.create.articles.valid_at(valid_datetime) }
          it { is_expected.to have_valid_at(valid_datetime, table: "articles") }
          it { is_expected.to have_transaction_at(time_current, table: "articles") }
        end

        context "with .ignore_bitemporal_datetime" do
          let(:relation) { Blog.create.articles.ignore_bitemporal_datetime }
          it { is_expected.to not_have_bitemporal_at(table: "articles") }
        end

        context "with unscoped" do
          let(:sql) { Article.unscoped { Blog.create.articles.to_sql } }
          it { is_expected.to not_have_bitemporal_at(table: "articles") }
        end
      end

      describe "call belongs_to associations" do
        let(:association_scope) { Blog.create.articles.create.association(:blog).scope }
        let(:relation) { association_scope }
        it { is_expected.to have_bitemporal_at(time_current, table: "blogs") }

        context "with .valid_at" do
          let(:valid_datetime) { "2019/01/01".in_time_zone }
          let(:relation) { association_scope.valid_at(valid_datetime) }
          it { is_expected.to have_valid_at(valid_datetime, table: "blogs") }
          it { is_expected.to have_transaction_at(time_current, table: "blogs") }
        end

        context "with .ignore_bitemporal_datetime" do
          let(:valid_datetime) { "2019/01/01".in_time_zone }
          let(:relation) { association_scope.ignore_bitemporal_datetime }
          it { is_expected.to not_have_bitemporal_at(table: "blogs") }
        end

        context "with unscoped" do
          let(:sql) { Blog.unscoped { association_scope.to_sql } }
          it { is_expected.to not_have_bitemporal_at(table: "blogs") }
        end
      end

      context "with `.find_at_time`" do
        let(:blog) { Blog.create }
        let(:find_datetime) { 1.days.since.round(6) }
        let(:relation) { Blog.find_at_time(find_datetime, blog.id).articles }
        it { is_expected.to have_valid_at(find_datetime, table: "articles") }
        it { is_expected.to have_transaction_at(time_current, table: "articles") }
      end
    end

    describe "through" do
      let(:blog) { Blog.create!(name: "tabelog").tap { |it| it.update(name: "sushilog") } }
      let(:user) { User.create!(name: "Jane").tap { |it| it.update(name: "Tom") } }
      let(:article) { user.articles.create!(title: "yakiniku", blog: blog).tap { |it| it.update(title: "sushi") } }

      context ".ignore_valid_datetime" do
        let(:relation) { blog.users.ignore_valid_datetime }
        it { is_expected.to not_have_valid_at(table: "users") }
        it { is_expected.to not_have_valid_at(table: "articles") }

        it { is_expected.to have_transaction_at(time_current, table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "articles") }
      end

      context ".valid_at" do
        let(:valid_datetime) { "2019/01/01".in_time_zone }
        let(:relation) { blog.users.valid_at(valid_datetime) }
        it { is_expected.to have_valid_at(valid_datetime, table: "users") }
        it { is_expected.to have_valid_at(valid_datetime, table: "articles") }

        it { is_expected.to have_transaction_at(time_current, table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "articles") }
      end

      context ".transaction_at" do
        let(:transaction_datetime) { "2019/01/01".in_time_zone }
        let(:relation) { blog.users.transaction_at(transaction_datetime) }
        it { is_expected.to have_valid_at(time_current, table: "users") }
        it { is_expected.to have_valid_at(time_current, table: "articles") }

        it { is_expected.to have_transaction_at(transaction_datetime, table: "users") }
        it { is_expected.to have_transaction_at(transaction_datetime, table: "articles") }
      end

      context ".find_at_time" do
        let(:blog) { Blog.create }
        let(:find_datetime) { 1.days.since.round(6) }
        let(:relation) { Blog.find_at_time(find_datetime, blog.id).users }
        it { is_expected.to have_valid_at(find_datetime, table: "users") }
        it { is_expected.to have_valid_at(find_datetime, table: "articles") }

        it { is_expected.to have_transaction_at(time_current, table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "articles") }

        context ".valid_at" do
          let(:valid_datetime) { "2019/01/1".in_time_zone }
          let(:relation) { Blog.find_at_time(find_datetime, blog.id).users.valid_at(valid_datetime) }
          it { is_expected.to have_valid_at(valid_datetime, table: "users") }
          it { is_expected.to have_valid_at(valid_datetime, table: "articles") }

          it { is_expected.to have_transaction_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "articles") }
        end
      end
    end

    context "with time zone" do
      let!(:old_time_zone) { Time.zone }
      let(:relation) { User.valid_at("2019/01/01 09:00") }
      before do
        Time.zone = "Tokyo"
      end
      after { Time.zone = old_time_zone }
      it { is_expected.to have_valid_at("2019-01-01 00:00:00".to_time, table: "users") }
      it { is_expected.to have_transaction_at(time_current, table: "users") }
    end
  end

  describe "bitemporal_option" do
    let(:time_current) { Time.current.round }
    let(:bitemporal_option) { Timecop.freeze(time_current) { relation.bitemporal_option } }
    subject { Timecop.freeze(time_current) { bitemporal_option } }

    context "default_scope" do
      let(:relation) { Blog.all }
      it { is_expected.to include(valid_datetime: time_current, transaction_datetime: time_current) }
    end

    context ".valid_at" do
      let(:valid_datetime) { "2019/01/1".in_time_zone }
      let(:relation) { Blog.valid_at(valid_datetime) }
      it { is_expected.to include(valid_datetime: valid_datetime, transaction_datetime: time_current) }

      context ".ignore_valid_datetime" do
        let(:relation) { Blog.valid_at(valid_datetime).ignore_valid_datetime }
        it { is_expected.not_to include(valid_datetime: time_current) }
        it { is_expected.to include(transaction_datetime: time_current) }
      end
    end

    context ".ignore_valid_datetime" do
      let(:relation) { Blog.ignore_valid_datetime }
      it { is_expected.not_to include(valid_datetime: time_current) }
      it { is_expected.to include(transaction_datetime: time_current) }

      context ".valid_at" do
        let(:valid_datetime) { "2019/01/1".in_time_zone }
        let(:relation) { Blog.ignore_valid_datetime.valid_at(valid_datetime) }
        it { is_expected.to include(valid_datetime: valid_datetime, transaction_datetime: time_current) }
      end
    end

    context "with `.transaction_at`" do
      let(:transaction_datetime) { "2019/01/1".in_time_zone }
      let(:relation) { Blog.transaction_at(transaction_datetime) }
      it { is_expected.to include(valid_datetime: time_current, transaction_datetime: transaction_datetime) }
    end

    context "with `.ignore_transaction_datetime`" do
      let(:relation) { Blog.ignore_transaction_datetime }
      it { is_expected.to include(valid_datetime: time_current) }
      it { is_expected.not_to include(transaction_datetime: time_current) }
    end
  end
end
