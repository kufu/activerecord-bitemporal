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
    let(:_01_01) { "2019/01/01".in_time_zone }
    let(:_06_01) { "2019/06/01".in_time_zone }
    let(:_09_01) { "2019/09/01".in_time_zone }
    let(:time_current) { Time.current.round }
    let(:sql) { relation.to_sql }
    define_method(:scan_once) { |x| satisfy("sql scan `#{x}` one?") { |sql| sql.scan(x).one? } }
    RSpec::Matchers.define_negated_matcher :not_scan, :scan_once

    define_method(:have_valid_at) { |datetime = Time.current, table:|
           scan_once(%{"#{table}"."valid_from"})
      .and scan_once(%{"#{table}"."valid_to"})
      .and include(%{"#{table}"."valid_from" <= '#{datetime.to_formatted_s(:db)}'})
      .and include(%{"#{table}"."valid_to" > '#{datetime.to_formatted_s(:db)}'})
    }
    define_method(:not_have_valid_at) { |table:|
           not_scan(%{"#{table}"."valid_from"})
      .and not_scan(%{"#{table}"."valid_to"})
    }
    define_method(:have_transaction_at) { |datetime, table:|
           scan_once(%{"#{table}"."transaction_from"})
      .and scan_once(%{"#{table}"."transaction_to"})
      .and include(%{"#{table}"."transaction_from" <= '#{datetime.to_formatted_s(:db)}'})
      .and include(%{"#{table}"."transaction_to" > '#{datetime.to_formatted_s(:db)}'})
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

    around { |e| Timecop.freeze(time_current) { e.run } }
    subject { sql }

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

      context ".where(String).ignore_bitemporal_datetime" do
        let(:relation) { User.where("age < 20").ignore_bitemporal_datetime }
        it { is_expected.to not_have_bitemporal_at(table: "users") }
        it { is_expected.to scan_once "age < 20" }
      end
    end

    describe ".except_valid_datetime" do
      let(:relation) { User.except_valid_datetime }
      it { is_expected.to not_have_valid_at(table: "users") }
      it { is_expected.to have_transaction_at(time_current, table: "users") }

      describe ".valid_at" do
        let(:valid_datetime) { "2019/01/01".in_time_zone }
        let(:relation) { User.except_valid_datetime.valid_at(valid_datetime) }
        it { is_expected.to have_valid_at(valid_datetime, table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "users") }
      end
    end

    describe ".except_transaction_datetime" do
      let(:relation) { User.except_transaction_datetime }
      it { is_expected.to have_valid_at(time_current, table: "users") }
      it { is_expected.to not_have_transaction_at(table: "users") }

      describe ".transaction_at" do
        let(:transaction_datetime) { "2019/01/01".in_time_zone }
        let(:relation) { User.except_transaction_datetime.transaction_at(transaction_datetime) }
        it { is_expected.to have_valid_at(time_current, table: "users") }
        it { is_expected.to have_transaction_at(transaction_datetime, table: "users") }
      end
    end

    describe ".except_bitemporal_datetime" do
      let(:relation) { User.except_bitemporal_datetime }
      it { is_expected.to not_have_bitemporal_at(table: "users") }

      describe ".valid_at" do
        let(:valid_datetime) { "2019/01/01".in_time_zone }
        let(:relation) { User.except_valid_datetime.valid_at(valid_datetime) }
        it { is_expected.to have_valid_at(valid_datetime, table: "users") }
        it { is_expected.to have_transaction_at(time_current, table: "users") }
      end

      describe ".transaction_at" do
        let(:transaction_datetime) { "2019/01/01".in_time_zone }
        let(:relation) { User.except_transaction_datetime.transaction_at(transaction_datetime) }
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

      describe ".except_valid_datetime" do
        let(:relation) { User.valid_at("2019/01/01").except_valid_datetime }
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

      describe ".transaction_at" do
        let(:transaction_datetime) { "2019/01/01".in_time_zone }
        let(:relation) { User.transaction_at("2019/05/01").transaction_at(transaction_datetime) }
        it { is_expected.to have_valid_at(time_current, table: "users") }
        it { is_expected.to have_transaction_at(transaction_datetime, table: "users") }
      end

      describe ".ignore_transaction_datetime" do
        let(:relation) { User.transaction_at("2019/01/01").ignore_transaction_datetime }
        it { is_expected.to have_valid_at(time_current, table: "users") }
        it { is_expected.to not_have_transaction_at(table: "users") }
      end

      describe ".except_transaction_datetime" do
        let(:relation) { User.transaction_at("2019/01/01").except_transaction_datetime }
        it { is_expected.to have_valid_at(time_current, table: "users") }
        it { is_expected.to not_have_transaction_at(table: "users") }
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

      describe ".ignore_bitemporal_datetime" do
        let(:relation) { User.bitemporal_at(bitemporal_datetime).ignore_bitemporal_datetime }
        it { is_expected.to not_have_transaction_at(table: "users") }
      end

      describe ".except_bitemporal_datetime" do
        let(:relation) { User.bitemporal_at(bitemporal_datetime).ignore_bitemporal_datetime }
        it { is_expected.to not_have_transaction_at(table: "users") }
      end

      context "duplicates" do
        let(:bitemporal_datetime) { "2019/01/01".in_time_zone }
        let(:relation) { User.bitemporal_at("2019/05/05").bitemporal_at(bitemporal_datetime) }
        it { is_expected.to have_bitemporal_at(bitemporal_datetime, table: "users") }
      end

      context "ActiveRecord::Bitemporal.valid_at" do
        let(:valid_datetime) { "2017/04/01".in_time_zone }
        let(:relation) { ActiveRecord::Bitemporal.valid_at(valid_datetime) { User.bitemporal_at(bitemporal_datetime) } }
        it { is_expected.to have_valid_at(valid_datetime, table: "users") }
        it { is_expected.to have_transaction_at(bitemporal_datetime, table: "users") }
      end

      context "ActiveRecord::Bitemporal.ignore_valid_datetime" do
        let(:relation) { ActiveRecord::Bitemporal.ignore_valid_datetime { User.bitemporal_at(bitemporal_datetime) } }
        it { is_expected.to not_have_valid_at(table: "users") }
        it { is_expected.to have_transaction_at(bitemporal_datetime, table: "users") }
      end

      context "ActiveRecord::Bitemporal.transaction_at" do
        let(:transaction_datetime) { "2017/04/01".in_time_zone }
        let(:relation) { ActiveRecord::Bitemporal.transaction_at(transaction_datetime) { User.bitemporal_at(bitemporal_datetime) } }
        it { is_expected.to have_valid_at(bitemporal_datetime, table: "users") }
        it { is_expected.to have_transaction_at(transaction_datetime, table: "users") }
      end

      context "ActiveRecord::Bitemporal.ignore_transaction_datetime" do
        let(:relation) { ActiveRecord::Bitemporal.ignore_transaction_datetime { User.bitemporal_at(bitemporal_datetime) } }
        it { is_expected.to have_valid_at(bitemporal_datetime, table: "users") }
        it { is_expected.to not_have_transaction_at(table: "users") }
      end
    end

    context "duplicates `valid_from_lt" do
      let(:relation) { User.valid_from_lt("2019/01/01").valid_from_lt("2019/03/03") }
      it { is_expected.to scan_once("valid_from").and scan_once("valid_to") }
      it { is_expected.to include %{"valid_from" < '2019-03-03 00:00:00'} }
      it { is_expected.to include %{"valid_to" > '#{time_current.to_formatted_s(:db)}'} }
      it { is_expected.to have_transaction_at(time_current, table: "users") }
    end

    context "duplicates `valid_from_lt` and `valid_from_lteq`" do
      let(:relation) { User.valid_from_lt("2019/01/01").valid_from_lteq("2019/03/03") }
      it { is_expected.to scan_once("valid_from").and scan_once("valid_to") }
      it { is_expected.to include %{"valid_from" <= '2019-03-03 00:00:00'} }
      it { is_expected.to include %{"valid_to" > '#{time_current.to_formatted_s(:db)}'} }
      it { is_expected.to have_transaction_at(time_current, table: "users") }
    end

    describe ".merge" do
      context "bitemporal_datetime" do
        context ".merge(.bitemporal_at)" do
          let(:relation) { User.merge(User.bitemporal_at(_01_01)) }
          it { is_expected.to have_bitemporal_at(_01_01, table: "users") }
        end

        context ".merge(.bitemporal_at.except_bitemporal_datetime)" do
          let(:relation) { User.merge(User.bitemporal_at(_01_01).except_bitemporal_datetime) }
          it { is_expected.to have_bitemporal_at(time_current, table: "users") }
        end

        context ".merge(.bitemporal_at.ignore_bitemporal_datetime.except_bitemporal_datetime)" do
          let(:relation) { User.merge(User.bitemporal_at(_01_01).ignore_bitemporal_datetime.except_bitemporal_datetime) }
          it { is_expected.to not_have_bitemporal_at(table: "users") }
        end

        context ".merge(.bitemporal_at.bitemporal_at.except_bitemporal_datetime)" do
          let(:relation) { User.merge(User.bitemporal_at(_06_01).bitemporal_at(_01_01).except_bitemporal_datetime) }
          it { is_expected.to have_bitemporal_at(time_current, table: "users") }
        end

        context ".merge(.ignore_bitemporal_datetime)" do
          let(:relation) { User.merge(User.ignore_bitemporal_datetime) }
          it { is_expected.to not_have_bitemporal_at(table: "users") }
        end

        context ".merge(.ignore_bitemporal_datetime.except_bitemporal_datetime)" do
          let(:relation) { User.merge(User.ignore_bitemporal_datetime.except_bitemporal_datetime) }
          it { is_expected.to not_have_bitemporal_at(table: "users") }
        end

        context ".merge(.ignore_bitemporal_datetime.except_bitemporal_datetime.except_bitemporal_datetime)" do
          let(:relation) { User.merge(User.ignore_bitemporal_datetime.except_bitemporal_datetime.except_bitemporal_datetime) }
          it { is_expected.to not_have_bitemporal_at(table: "users") }
        end

        context ".merge(.ignore_bitemporal_datetime.bitepmoral_at.except_bitemporal_datetime)" do
          let(:relation) { User.merge(User.ignore_bitemporal_datetime.bitemporal_at(_01_01).except_bitemporal_datetime) }
          it { is_expected.to have_bitemporal_at(time_current, table: "users") }
        end

        context ".merge(.ignore_bitemporal_datetime.bitepmoral_at.except_bitemporal_datetime.except_bitemporal_datetime)" do
          let(:relation) { User.merge(User.ignore_bitemporal_datetime.bitemporal_at(_01_01).except_bitemporal_datetime.except_bitemporal_datetime) }
          it { is_expected.to have_bitemporal_at(time_current, table: "users") }
        end

        context ".merge(.ignore_bitemporal_datetime.bitepmoral_at.except_bitemporal_datetime.bitemporal_at)" do
          let(:relation) { User.merge(User.ignore_bitemporal_datetime.bitemporal_at(_01_01).except_bitemporal_datetime.bitemporal_at(_01_01)) }
          it { is_expected.to have_bitemporal_at(_01_01, table: "users") }
        end

        context ".merge(.ignore_bitemporal_datetime.bitepmoral_at.except_bitemporal_datetime.bitemporal_at.except_bitemporal_datetime)" do
          let(:relation) { User.merge(User.ignore_bitemporal_datetime.bitemporal_at(_01_01).except_bitemporal_datetime.bitemporal_at(_01_01).except_bitemporal_datetime) }
          it { is_expected.to have_bitemporal_at(time_current, table: "users") }
        end

        context ".merge(.except_valid_datetime)" do
          let(:relation) { User.merge(User.except_valid_datetime) }
          it { is_expected.to have_bitemporal_at(time_current, table: "users") }
        end

        context ".merge(.except_valid_datetime.bitemporal_at)" do
          let(:relation) { User.merge(User.except_valid_datetime.bitemporal_at(_01_01)) }
          it { is_expected.to have_bitemporal_at(_01_01, table: "users") }
        end

        context ".merge(.bitemporal_at).bitemporal_at" do
          let(:relation) { User.merge(User.bitemporal_at(_06_01)).bitemporal_at(_01_01) }
          it { is_expected.to have_bitemporal_at(_01_01, table: "users") }
        end

        context ".merge(.ignore_bitemporal_datetime).bitemporal_at" do
          let(:relation) { User.merge(User.ignore_bitemporal_datetime).bitemporal_at(_01_01) }
          it { is_expected.to have_bitemporal_at(_01_01, table: "users") }
        end

        context ".merge(.except_valid_datetime).bitemporal_at" do
          let(:relation) { User.merge(User.except_valid_datetime).bitemporal_at(_01_01) }
          it { is_expected.to have_bitemporal_at(_01_01, table: "users") }
        end

        context ".bitemporal_at.merge(.bitemporal_at)" do
          let(:relation) { User.bitemporal_at(_06_01).merge(User.bitemporal_at(_01_01)) }
          it { is_expected.to have_bitemporal_at(_01_01, table: "users") }
        end

        context ".bitemporal_at.merge(.ignore_bitemporal_datetime)" do
          let(:relation) { User.bitemporal_at(_01_01).merge(User.ignore_bitemporal_datetime) }
          it { is_expected.to not_have_bitemporal_at(table: "users") }
        end

        context ".bitemporal_at.merge(.ignore_bitemporal_datetime.except_bitemporal_datetime)" do
          let(:relation) { User.bitemporal_at(_01_01).merge(User.ignore_bitemporal_datetime.except_bitemporal_datetime) }
          it { is_expected.to not_have_bitemporal_at(table: "users") }
        end

        context ".bitemporal_at.merge(.except_bitemporal_datetime)" do
          let(:relation) { User.bitemporal_at(_01_01).merge(User.except_bitemporal_datetime) }
          it { is_expected.to have_bitemporal_at(_01_01, table: "users") }
        end

        context ".bitemporal_at.merge(.bitemporal_at).bitemporal_at" do
          let(:relation) { User.bitemporal_at(_06_01).merge(User.bitemporal_at(_09_01)).bitemporal_at(_01_01) }
          it { is_expected.to have_bitemporal_at(_01_01, table: "users") }
        end

        context ".bitemporal_at.merge(.ignore_bitemporal_datetime).bitemporal_at" do
          let(:relation) { User.bitemporal_at(_09_01).merge(User.ignore_bitemporal_datetime).bitemporal_at(_01_01) }
          it { is_expected.to have_bitemporal_at(_01_01, table: "users") }
        end

        context ".bitemporal_at.merge(.except_bitemporal_datetime).bitemporal_at" do
          let(:relation) { User.bitemporal_at(_09_01).merge(User.except_bitemporal_datetime).bitemporal_at(_01_01) }
          it { is_expected.to have_bitemporal_at(_01_01, table: "users") }
        end
      end

      context "valid_datetime" do
        context ".merge(.valid_at)" do
          let(:relation) { User.merge(User.valid_at(_01_01)) }
          it { is_expected.to have_valid_at(_01_01, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".merge(.valid_at.except_bitemporal_datetime)" do
          let(:relation) { User.merge(User.valid_at(_01_01).except_valid_datetime) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".merge(.valid_at.valid_at.except_bitemporal_datetime)" do
          let(:relation) { User.merge(User.valid_at(_06_01).valid_at(_01_01).except_valid_datetime) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".merge(.ignore_valid_datetime)" do
          let(:relation) { User.merge(User.ignore_valid_datetime) }
          it { is_expected.to not_have_valid_at(table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".merge(.ignore_valid_datetime.except_valid_datetime)" do
          let(:relation) { User.merge(User.ignore_valid_datetime.except_valid_datetime) }
          it { is_expected.to not_have_valid_at(table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".merge(.ignore_valid_datetime.valid_at)" do
          let(:relation) { User.merge(User.ignore_valid_datetime.valid_at(_01_01)) }
          it { is_expected.to have_valid_at(_01_01, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".merge(.ignore_valid_datetime.valid_at.except_valid_datetime)" do
          let(:relation) { User.merge(User.ignore_valid_datetime.valid_at(_01_01).except_valid_datetime) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".merge(.ignore_valid_datetime.valid_at.except_valid_datetime.except_valid_datetime)" do
          let(:relation) { User.merge(User.ignore_valid_datetime.valid_at(_01_01).except_valid_datetime.except_valid_datetime) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".merge(.except_valid_datetime)" do
          let(:relation) { User.merge(User.except_valid_datetime) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".merge(.except_valid_datetime" do
          let(:relation) { User.merge(User.except_valid_datetime.valid_at(_01_01)) }
          it { is_expected.to have_valid_at(_01_01, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".merge(.valid_at).valid_at" do
          let(:relation) { User.merge(User.valid_at(_06_01)).valid_at(_01_01) }
          it { is_expected.to have_valid_at(_01_01, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".merge(.ignore_valid_datetime).valid_at" do
          let(:relation) { User.merge(User.ignore_valid_datetime).valid_at(_01_01) }
          it { is_expected.to have_valid_at(_01_01, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".merge(.except_valid_datetime).valid_at" do
          let(:relation) { User.merge(User.except_valid_datetime).valid_at(_01_01) }
          it { is_expected.to have_valid_at(_01_01, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".valid_at.merge(.valid_at)" do
          let(:relation) { User.valid_at(_06_01).merge(User.valid_at(_01_01)) }
          it { is_expected.to have_valid_at(_01_01, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".valid_at.merge(.ignore_valid_datetime)" do
          let(:relation) { User.valid_at(_01_01).merge(User.ignore_valid_datetime) }
          it { is_expected.to not_have_valid_at(table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".valid_at.merge(.ignore_valid_datetime.except_valid_datetime)" do
          let(:relation) { User.valid_at(_01_01).merge(User.ignore_valid_datetime.except_valid_datetime) }
          it { is_expected.to not_have_valid_at(table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".valid_at.merge(.except_valid_datetime)" do
          let(:relation) { User.valid_at(_01_01).merge(User.except_valid_datetime) }
          it { is_expected.to have_valid_at(_01_01, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".valid_at.merge(.valid_at).valid_at" do
          let(:relation) { User.valid_at(_06_01).merge(User.valid_at(_09_01)).valid_at(_01_01) }
          it { is_expected.to have_valid_at(_01_01, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".valid_at.merge(.ignore_valid_datetime).valid_at" do
          let(:relation) { User.valid_at(_09_01).merge(User.ignore_valid_datetime).valid_at(_01_01) }
          it { is_expected.to have_valid_at(_01_01, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".valid_at.merge(.except_valid_datetime).valid_at" do
          let(:relation) { User.valid_at(_09_01).merge(User.except_valid_datetime).valid_at(_01_01) }
          it { is_expected.to have_valid_at(_01_01, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end
      end

      context "transaction_datetime" do
        context ".merge(.transaction_at)" do
          let(:relation) { User.merge(User.transaction_at(_01_01)) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(_01_01, table: "users") }
        end

        context ".merge(.transaction_at.except_transaction_datetime)" do
          let(:relation) { User.merge(User.transaction_at(_01_01).except_transaction_datetime) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".merge(.transaction_at.transaction_at.except_transaction_datetime)" do
          let(:relation) { User.merge(User.transaction_at(_06_01).transaction_at(_01_01).except_transaction_datetime) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".merge(.ignore_transaction_datetime)" do
          let(:relation) { User.merge(User.ignore_transaction_datetime) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to not_have_transaction_at(table: "users") }
        end

        context ".merge(.ignore_transaction_datetime.except_transaction_datetime)" do
          let(:relation) { User.merge(User.ignore_transaction_datetime.except_transaction_datetime) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to not_have_transaction_at(table: "users") }
        end

        context ".merge(.ignore_transaction_datetime.transaction_at.except_transaction_datetime)" do
          let(:relation) { User.merge(User.ignore_transaction_datetime.transaction_at(_01_01).except_transaction_datetime) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".merge(.ignore_transaction_datetime.transaction_at.except_transaction_datetime.except_transaction_datetime)" do
          let(:relation) { User.merge(User.ignore_transaction_datetime.transaction_at(_01_01).except_transaction_datetime.except_transaction_datetime) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".merge(.ignore_transaction_datetime.transaction_at.except_transaction_datetime.transaction_at)" do
          let(:relation) { User.merge(User.ignore_transaction_datetime.transaction_at(_01_01).except_transaction_datetime.transaction_at(_01_01)) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(_01_01, table: "users") }
        end

        context ".merge(.except_transaction_datetime)" do
          let(:relation) { User.merge(User.except_transaction_datetime) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end

        context ".merge(.except_transaction_datetime.transaction_at)" do
          let(:relation) { User.merge(User.except_transaction_datetime.transaction_at(_01_01)) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(_01_01, table: "users") }
        end

        context ".merge(.transaction_at).transaction_at" do
          let(:relation) { User.merge(User.transaction_at(_06_01)).transaction_at(_01_01) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(_01_01, table: "users") }
        end

        context ".merge(.ignore_transaction_datetime).transaction_at" do
          let(:relation) { User.merge(User.ignore_transaction_datetime).transaction_at(_01_01) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(_01_01, table: "users") }
        end

        context ".merge(.ignore_transaction_datetime.except_transaction_datetime).transaction_at" do
          let(:relation) { User.merge(User.ignore_transaction_datetime.except_transaction_datetime).transaction_at(_01_01) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(_01_01, table: "users") }
        end

        context ".merge(.ignore_transaction_datetime.except_transaction_datetime).transaction_at" do
          let(:relation) { User.merge(User.ignore_transaction_datetime.except_transaction_datetime.except_transaction_datetime).transaction_at(_01_01) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(_01_01, table: "users") }
        end

        context ".merge(.except_transaction_datetime).transaction_at" do
          let(:relation) { User.merge(User.except_transaction_datetime).transaction_at(_01_01) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(_01_01, table: "users") }
        end

        context ".transaction_at.merge(.transaction_at)" do
          let(:relation) { User.transaction_at(_06_01).merge(User.transaction_at(_01_01)) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(_01_01, table: "users") }
        end

        context ".transaction_at.merge(.ignore_transaction_datetime)" do
          let(:relation) { User.transaction_at(_01_01).merge(User.ignore_transaction_datetime) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to not_have_transaction_at(table: "users") }
        end

        context ".transaction_at.merge(.ignore_transaction_datetime.except_transaction_datetime)" do
          let(:relation) { User.transaction_at(_01_01).merge(User.ignore_transaction_datetime.except_transaction_datetime) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to not_have_transaction_at(table: "users") }
        end

        context ".transaction_at.merge(.except_transaction_datetime)" do
          let(:relation) { User.transaction_at(_01_01).merge(User.except_transaction_datetime) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(_01_01, table: "users") }
        end

        context ".transaction_at.merge(.transaction_at).transaction_at" do
          let(:relation) { User.transaction_at(_06_01).merge(User.transaction_at(_09_01)).transaction_at(_01_01) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(_01_01, table: "users") }
        end

        context ".transaction_at.merge(.ignore_transaction_datetime).transaction_at" do
          let(:relation) { User.transaction_at(_09_01).merge(User.ignore_transaction_datetime).transaction_at(_01_01) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(_01_01, table: "users") }
        end

        context ".transaction_at.merge(.except_valid_datetime).transaction_at" do
          let(:relation) { User.transaction_at(_09_01).merge(User.except_valid_datetime).transaction_at(_01_01) }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(_01_01, table: "users") }
        end
      end

      context "default_scope" do
        let(:relation) { User.where(name: "mami").merge(Timecop.freeze(_01_01) { User.where(name: "homu") }) }
        it { is_expected.to have_bitemporal_at(_01_01, table: "users") }
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
        let(:relation) { ActiveRecord::Bitemporal.valid_at(valid_datetime) { ActiveRecord::Bitemporal.valid_at!(valid_datetime2) { User.all } } }
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
          let(:user_valid_datetime) { "2016/01/05".in_time_zone }
          let(:relation) { ActiveRecord::Bitemporal.valid_at!(valid_datetime) { User.valid_at(user_valid_datetime) } }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end
      end

      describe ".valid_at" do
        let(:user_valid_datetime) { "2016/01/05".in_time_zone }
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

    describe "ActiveRecord::Bitemporal.transaction_at" do
      let(:transaction_datetime) { "2019/05/05".in_time_zone }
      let(:relation) { ActiveRecord::Bitemporal.transaction_at(transaction_datetime) { User.all } }
      it { is_expected.to have_valid_at(time_current, table: "users") }
      it { is_expected.to have_transaction_at(transaction_datetime, table: "users") }

      context "transaction_datetime is nil" do
        let(:transaction_datetime) { nil }
        it { is_expected.to have_bitemporal_at(time_current, table: "users") }
      end

      describe ".transaction_at" do
        let(:user_transaction_datetime) { "2019/05/05".in_time_zone }
        let(:relation) { ActiveRecord::Bitemporal.transaction_at(transaction_datetime) { User.transaction_at(user_transaction_datetime) } }
        it { is_expected.to have_valid_at(time_current, table: "users") }
        it { is_expected.to have_transaction_at(user_transaction_datetime, table: "users") }
      end

      context "with ActiveRecord::Bitemporal.ignore_transaction_datetime" do
        let(:relation) { ActiveRecord::Bitemporal.transaction_at(transaction_datetime) { ActiveRecord::Bitemporal.ignore_transaction_datetime { User.all } } }
        it { is_expected.to have_valid_at(time_current, table: "users") }
        it { is_expected.to not_have_transaction_at(table: "users") }
      end

      context ".ignore_transaction_datetime" do
        let(:relation) { ActiveRecord::Bitemporal.transaction_at(transaction_datetime) { User.ignore_transaction_datetime } }
        it { is_expected.to have_valid_at(time_current, table: "users") }
        it { is_expected.to not_have_transaction_at(table: "users") }
      end

      describe "ActiveRecord::Bitemporal.transaction_at!" do
        let(:transaction_datetime2) { "2019/06/06".in_time_zone }
        let(:relation) { ActiveRecord::Bitemporal.transaction_at(transaction_datetime) { ActiveRecord::Bitemporal.transaction_at!(transaction_datetime2) { User.all } } }
        it { is_expected.to have_valid_at(time_current, table: "users") }
        it { is_expected.to have_transaction_at(transaction_datetime2, table: "users") }
      end
    end

    describe "ActiveRecord::Bitemporal.transaction_at!" do
      let(:transaction_datetime) { "2019/05/05".in_time_zone }
      let(:relation) { ActiveRecord::Bitemporal.transaction_at!(transaction_datetime) { User.all } }
      it { is_expected.to have_valid_at(time_current, table: "users") }
      it { is_expected.to have_transaction_at(transaction_datetime, table: "users") }

      context "transaction_datetime is nil" do
        let(:transaction_datetime) { nil }
        it { is_expected.to have_bitemporal_at(time_current, table: "users") }

        context "with .transaction_at" do
          let(:user_transaction_datetime) { "2016/01/05".in_time_zone }
          let(:relation) { ActiveRecord::Bitemporal.transaction_at!(transaction_datetime) { User.transaction_at(user_transaction_datetime) } }
          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }
        end
      end

      describe ".transaction_at" do
        let(:user_transaction_datetime) { "2016/01/05".in_time_zone }
        let(:relation) { ActiveRecord::Bitemporal.transaction_at!(transaction_datetime) { User.transaction_at(user_transaction_datetime) } }
        it { is_expected.to have_valid_at(time_current, table: "users") }
        it { is_expected.to have_transaction_at(transaction_datetime, table: "users") }
      end

      context ".ignore_transaction_datetime" do
        let(:relation) { ActiveRecord::Bitemporal.transaction_at!(transaction_datetime) { User.ignore_transaction_datetime } }
        it { is_expected.to have_valid_at(time_current, table: "users") }
        it { is_expected.to not_have_transaction_at(table: "users") }
      end
    end

    describe "ActiveRecord::Bitemporal.ignore_transaction_datetime" do
      let(:relation) { ActiveRecord::Bitemporal.ignore_transaction_datetime { User.all } }
      it { is_expected.to have_valid_at(time_current, table: "users") }
      it { is_expected.to not_have_transaction_at(table: "users") }

      context "with ActiveRecord::Bitemporal.transaction_at" do
        let(:transaction_datetime) { "2019/05/05".in_time_zone }
        let(:relation) { ActiveRecord::Bitemporal.ignore_transaction_datetime { ActiveRecord::Bitemporal.transaction_at(transaction_datetime) { User.all } } }
        it { is_expected.to have_valid_at(time_current, table: "users") }
        it { is_expected.to have_transaction_at(transaction_datetime, table: "users") }
      end

      context "with .transaction_at" do
        let(:transaction_datetime) { "2019/05/05".in_time_zone }
        let(:relation) { ActiveRecord::Bitemporal.ignore_transaction_datetime { User.transaction_at(transaction_datetime) } }
        it { is_expected.to have_valid_at(time_current, table: "users") }
        it { is_expected.to have_transaction_at(transaction_datetime, table: "users") }
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

        context "with call to_sql in `ActiveRecord::Bitemporal.transaction_at`" do
          let(:transaction_datetime) { "2019/01/01".in_time_zone }
          let(:sql) { ActiveRecord::Bitemporal.transaction_at(transaction_datetime) { Blog.joins(:articles).to_sql } }
          it { is_expected.to have_valid_at(time_current, table: "blogs") }
          it { is_expected.to have_transaction_at(transaction_datetime, table: "blogs") }
          it { is_expected.to have_valid_at(time_current, table: "articles") }
          it { is_expected.to have_transaction_at(transaction_datetime, table: "articles") }
        end

        context "with call to_sql in `ActiveRecord::Bitemporal.valid_at` and `ActiveRecord::Bitemporal.transaction_at`" do
          let(:valid_datetime) { "2019/01/01".in_time_zone }
          let(:transaction_datetime) { "2019/02/01".in_time_zone }
          let(:sql) {
            ActiveRecord::Bitemporal.valid_at(valid_datetime) {
              ActiveRecord::Bitemporal.transaction_at(transaction_datetime) { Blog.joins(:articles).to_sql }
            }
          }
          it { is_expected.to have_valid_at(valid_datetime, table: "blogs") }
          it { is_expected.to have_transaction_at(transaction_datetime, table: "blogs") }
          it { is_expected.to have_valid_at(valid_datetime, table: "articles") }
          it { is_expected.to have_transaction_at(transaction_datetime, table: "articles") }
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

          it { is_expected.to have_transaction_at(time_current, table: "blogs") }
          it { is_expected.to have_transaction_at(time_current, table: "articles") }

          context "with call to_sql in `ActiveRecord::Bitemporal.valid_at`" do
            let(:valid_datetime) { "2019/01/01".in_time_zone }
            let(:sql) { ActiveRecord::Bitemporal.valid_at(valid_datetime) { relation.to_sql } }

            it { is_expected.to have_valid_at(valid_datetime, table: "blogs") }
            it { is_expected.to have_valid_at(valid_datetime, table: "articles") }

            it { is_expected.to have_transaction_at(time_current, table: "blogs") }
            it { is_expected.to have_transaction_at(time_current, table: "articles") }
          end

          context "with call to_sql in `ActiveRecord::Bitemporal.transaction_at`" do
            let(:transaction_datetime) { "2019/01/01".in_time_zone }
            let(:sql) { ActiveRecord::Bitemporal.transaction_at(transaction_datetime) { relation.to_sql } }

            it { is_expected.to have_valid_at(time_current, table: "blogs") }
            it { is_expected.to have_valid_at(time_current, table: "articles") }

            it { is_expected.to have_transaction_at(transaction_datetime, table: "blogs") }
            it { is_expected.to have_transaction_at(transaction_datetime, table: "articles") }
          end
        end

        # The behavior of `.josins.left_joins` has changed in Rails 6.0
        # Only supports Rails 5.x
        # see: https://github.com/rails/rails/commit/8f05035b7e595e2086759ee10ec9df9431e5e351
        if ActiveRecord::VERSION::MAJOR <= 5
          describe ".left_joins with rails 5.x" do
            let(:relation) { Blog.joins(:articles).left_joins(:articles) }

            it { is_expected.to have_valid_at(time_current, table: "articles_blogs") }
            it { is_expected.to have_transaction_at(time_current, table: "articles_blogs") }

            context "with call to_sql in `ActiveRecord::Bitemporal.valid_at`" do
              let(:valid_datetime) { "2019/01/01".in_time_zone }
              let(:sql) { ActiveRecord::Bitemporal.valid_at(valid_datetime) { relation.to_sql } }

              it { is_expected.to have_valid_at(valid_datetime, table: "articles_blogs") }
              it { is_expected.to have_transaction_at(time_current, table: "articles_blogs") }
            end

            context "with call to_sql in `ActiveRecord::Bitemporal.transaction_at`" do
              let(:transaction_datetime) { "2019/01/01".in_time_zone }
              let(:sql) { ActiveRecord::Bitemporal.transaction_at(transaction_datetime) { relation.to_sql } }

              it { is_expected.to have_valid_at(time_current, table: "articles_blogs") }
              it { is_expected.to have_transaction_at(transaction_datetime, table: "articles_blogs") }
            end
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

        context "with .transaction_at" do
          let(:transaction_datetime) { "2019/01/01".in_time_zone }
          let(:relation) { Blog.create.articles.transaction_at(transaction_datetime) }
          it { is_expected.to have_valid_at(time_current, table: "articles") }
          it { is_expected.to have_transaction_at(transaction_datetime, table: "articles") }
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

        context "with .transaction_at" do
          let(:transaction_datetime) { "2019/01/01".in_time_zone }
          let(:relation) { association_scope.transaction_at(transaction_datetime) }
          it { is_expected.to have_valid_at(time_current, table: "blogs") }
          it { is_expected.to have_transaction_at(transaction_datetime, table: "blogs") }
        end

        context "with .ignore_bitemporal_datetime" do
          let(:transaction_datetime) { "2019/01/01".in_time_zone }
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

      context ".ignore_transaction_datetime" do
        let(:relation) { blog.users.ignore_transaction_datetime }
        it { is_expected.to have_valid_at(time_current, table: "users") }
        it { is_expected.to have_valid_at(time_current, table: "articles") }

        it { is_expected.to not_have_transaction_at(table: "users") }
        it { is_expected.to not_have_transaction_at(table: "articles") }
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

    describe "Supported ActiveRecord methods" do
      describe ".scoping" do
        describe "with .valid_at" do
          let(:relation) { User.all }
          let(:scoping_valid_datetime) { "2019/01/1".in_time_zone }
          around { |e| User.valid_at(scoping_valid_datetime).scoping { e.run } }

          it { is_expected.to have_valid_at(scoping_valid_datetime, table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }

          context "with .valid_at" do
            let(:valid_datetime) { "2019/04/1".in_time_zone }
            let(:relation) { User.valid_at(valid_datetime) }

            it { is_expected.to have_valid_at(valid_datetime, table: "users") }
            it { is_expected.to have_transaction_at(time_current, table: "users") }
          end

          context "with .transaction_at" do
            let(:transaction_datetime) { "2019/04/1".in_time_zone }
            let(:relation) { User.transaction_at(transaction_datetime) }

            it { is_expected.to have_valid_at(scoping_valid_datetime, table: "users") }
            it { is_expected.to have_transaction_at(transaction_datetime, table: "users") }
          end

          context "other model query" do
            let(:relation) { Article.all }

            it { is_expected.to have_bitemporal_at(time_current, table: "articles") }
          end
        end

        describe "with .ignore_valid_datetime" do
          let(:relation) { User.all }
          around { |e| User.ignore_valid_datetime.scoping { e.run } }

          it { is_expected.to not_have_valid_at(table: "users") }
          it { is_expected.to have_transaction_at(time_current, table: "users") }

          context "with .valid_at" do
            let(:valid_datetime) { "2019/04/1".in_time_zone }
            let(:relation) { User.valid_at(valid_datetime) }

            it { is_expected.to have_valid_at(valid_datetime, table: "users") }
            it { is_expected.to have_transaction_at(time_current, table: "users") }
          end

          context "with .transaction_at" do
            let(:transaction_datetime) { "2019/04/1".in_time_zone }
            let(:relation) { User.transaction_at(transaction_datetime) }

            it { is_expected.to not_have_valid_at(table: "users") }
            it { is_expected.to have_transaction_at(transaction_datetime, table: "users") }
          end
        end

        describe "with .transaction_at" do
          let(:relation) { User.all }
          let(:scoping_transaction_datetime) { "2019/01/1".in_time_zone }
          around { |e| User.transaction_at(scoping_transaction_datetime).scoping { e.run } }

          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to have_transaction_at(scoping_transaction_datetime, table: "users") }

          context "with .valid_at" do
            let(:valid_datetime) { "2019/04/1".in_time_zone }
            let(:relation) { User.valid_at(valid_datetime) }

            it { is_expected.to have_valid_at(valid_datetime, table: "users") }
            it { is_expected.to have_transaction_at(scoping_transaction_datetime, table: "users") }
          end

          context "with .transaction_at" do
            let(:transaction_datetime) { "2019/04/1".in_time_zone }
            let(:relation) { User.transaction_at(transaction_datetime) }

            it { is_expected.to have_valid_at(time_current, table: "users") }
            it { is_expected.to have_transaction_at(transaction_datetime, table: "users") }
          end

          context "other model query" do
            let(:relation) { Article.all }

            it { is_expected.to have_bitemporal_at(time_current, table: "articles") }
          end
        end

        describe "with .ignore_transaction_datetime" do
          let(:relation) { User.all }
          around { |e| User.ignore_transaction_datetime.scoping { e.run } }

          it { is_expected.to have_valid_at(time_current, table: "users") }
          it { is_expected.to not_have_transaction_at(table: "users") }

          context "with .valid_at" do
            let(:valid_datetime) { "2019/04/1".in_time_zone }
            let(:relation) { User.valid_at(valid_datetime) }

            it { is_expected.to have_valid_at(valid_datetime, table: "users") }
            it { is_expected.to not_have_transaction_at(table: "users") }
          end

          context "with .transaction_at" do
            let(:transaction_datetime) { "2019/04/1".in_time_zone }
            let(:relation) { User.transaction_at(transaction_datetime) }

            it { is_expected.to have_valid_at(time_current, table: "users") }
            it { is_expected.to have_transaction_at(transaction_datetime, table: "users") }
          end
        end

        describe "with .ignore_bitemporal_datetime" do
          let(:relation) { User.all }
          around { |e| User.ignore_bitemporal_datetime.scoping { e.run } }

          it { is_expected.to not_have_bitemporal_at(table: "users") }

          context "with .valid_at" do
            let(:valid_datetime) { "2019/04/1".in_time_zone }
            let(:relation) { User.valid_at(valid_datetime) }

            it { is_expected.to have_valid_at(valid_datetime, table: "users") }
            it { is_expected.to not_have_transaction_at(table: "users") }
          end
        end

        # NOTE: Rails 6.0 is not supported.
        #     > Association loading isn't to be affected by scoping consistently whether preloaded / eager loaded or not, with the exception of unscoped.
        #     https://github.com/rails/rails/blob/v6.0.0/activerecord/CHANGELOG.md#rails-600rc1-april-24-2019
        xdescribe "with association" do
          let(:relation) { Blog.create.articles }
          let(:scoping_valid_datetime) { "2019/01/1".in_time_zone }
          around { |e| Article.valid_at(scoping_valid_datetime).scoping { e.run } }

          it { is_expected.to have_valid_at(scoping_valid_datetime, table: "articles") }
          it { is_expected.to have_transaction_at(time_current, table: "articles") }
        end
      end

      describe ".unscoped" do
        let(:relation) { User.all }
        around { |e| User.unscoped { e.run } }

        it { is_expected.to not_have_bitemporal_at(table: "users") }

        context "with .valid_at" do
          let(:valid_datetime) { "2019/04/1".in_time_zone }
          let(:relation) { User.valid_at(valid_datetime) }

          it { is_expected.to have_valid_at(valid_datetime, table: "users") }
          it { is_expected.to not_have_transaction_at(table: "users") }
        end

        context "with .transaction_at" do
          let(:transaction_datetime) { "2019/04/1".in_time_zone }
          let(:relation) { User.transaction_at(transaction_datetime) }

          it { is_expected.to not_have_valid_at(table: "users") }
          it { is_expected.to have_transaction_at(transaction_datetime, table: "users") }
        end

        context "other model query" do
          let(:relation) { Article.all }

          it { is_expected.to have_bitemporal_at(time_current, table: "articles") }
        end
      end
    end

    context "with where(Arel.sql)" do
      let!(:blog) { Blog.create(name: "Ruby") }
      let(:relation) { Blog.where(Arel.sql("valid_from").lteq(Time.current)) }
      subject { relation }
      it { is_expected.to have_attributes(first: blog) }
    end

    describe "preloading" do
      def sql_log(&block)
        old_logger = ActiveRecord::Base.logger
        old_colorize_logging = ActiveSupport::LogSubscriber.colorize_logging
        ActiveSupport::LogSubscriber.colorize_logging = false
        output = StringIO.new
        ActiveRecord::Base.logger = Logger.new(output, formatter: -> (severity, time, progname, msg) {
          "#{msg&.[](/(SELECT.*)$/)}\n"
        })
        ActiveRecord::Base.connection.unprepared_statement(&block)
        ActiveRecord::Base.logger
        output.string
      end
      define_method(:blogs_sql) { |matcher| satisfy { |sql, _| expect(sql).to matcher } }
      define_method(:articles_sql) { |matcher| satisfy { |_, sql| expect(sql).to matcher } }

      let(:sql) { Array(sql_log { relation.to_a.first.articles.load }.split("\n")) }
      before { Blog.create(valid_from: "2000/01/01", transaction_from: "2000/01/01").articles.create(valid_from: "2000/01/01", transaction_from: "2000/01/01") }

      context ".joins" do
        let(:relation) { Blog.joins(:articles) }

        # INNER JOIN
        it { is_expected.to blogs_sql scan_once 'INNER JOIN "articles"' }
        it { is_expected.to blogs_sql have_valid_at(time_current, table: "articles") }
        it { is_expected.to blogs_sql have_transaction_at(time_current, table: "articles") }
        # WHERE
        it { is_expected.to blogs_sql have_valid_at(time_current, table: "blogs") }
        it { is_expected.to blogs_sql have_transaction_at(time_current, table: "blogs") }
        # load association
        it { is_expected.to articles_sql have_valid_at(time_current, table: "articles") }
        it { is_expected.to articles_sql have_transaction_at(time_current, table: "articles") }

        context "with `ignore_valid_datetime`" do
          let(:relation) { Blog.ignore_valid_datetime.joins(:articles) }

          # INNER JOIN
          it { is_expected.to blogs_sql scan_once 'INNER JOIN "articles"' }
          it { is_expected.to blogs_sql not_have_valid_at(table: "articles") }
          it { is_expected.to blogs_sql have_transaction_at(time_current, table: "articles") }
          # WHERE
          it { is_expected.to blogs_sql not_have_valid_at(table: "blogs") }
          it { is_expected.to blogs_sql have_transaction_at(time_current, table: "blogs") }
          # load association
          it { is_expected.to articles_sql have_valid_at(time_current, table: "articles") }
          it { is_expected.to articles_sql have_transaction_at(time_current, table: "articles") }
        end

        context "with `valid_at`" do
          let(:valid_datetime) { "2019/01/01".in_time_zone }
          let(:relation) { Blog.valid_at(valid_datetime).joins(:articles) }

          # INNER JOIN
          it { is_expected.to blogs_sql scan_once 'INNER JOIN "articles"' }
          it { is_expected.to blogs_sql have_valid_at(valid_datetime, table: "articles") }
          it { is_expected.to blogs_sql have_transaction_at(time_current, table: "articles") }
          # WHERE
          it { is_expected.to blogs_sql have_valid_at(valid_datetime, table: "blogs") }
          it { is_expected.to blogs_sql have_transaction_at(time_current, table: "blogs") }
          # load association
          it { is_expected.to articles_sql have_valid_at(valid_datetime, table: "articles") }
          it { is_expected.to articles_sql have_transaction_at(time_current, table: "articles") }
        end

        context "with `ignore_transaction_datetime`" do
          let(:relation) { Blog.ignore_transaction_datetime.joins(:articles) }

          # INNER JOIN
          it { is_expected.to blogs_sql scan_once 'INNER JOIN "articles"' }
          it { is_expected.to blogs_sql have_valid_at(time_current, table: "articles") }
          it { is_expected.to blogs_sql not_have_transaction_at(table: "articles") }
          # WHERE
          it { is_expected.to blogs_sql have_valid_at(time_current, table: "blogs") }
          it { is_expected.to blogs_sql not_have_transaction_at(table: "blogs") }
          # load association
          it { is_expected.to articles_sql have_valid_at(time_current, table: "articles") }
          it { is_expected.to articles_sql have_transaction_at(time_current, table: "articles") }
        end

        context "with `transaction_at`" do
          let(:transaction_datetime) { "2019/01/01".in_time_zone }
          let(:relation) { Blog.transaction_at(transaction_datetime).joins(:articles) }

          # INNER JOIN
          it { is_expected.to blogs_sql scan_once 'INNER JOIN "articles"' }
          it { is_expected.to blogs_sql have_valid_at(time_current, table: "articles") }
          it { is_expected.to blogs_sql have_transaction_at(transaction_datetime, table: "articles") }
          # WHERE
          it { is_expected.to blogs_sql have_valid_at(time_current, table: "blogs") }
          it { is_expected.to blogs_sql have_transaction_at(transaction_datetime, table: "blogs") }
          # load association
          it { is_expected.to articles_sql have_valid_at(time_current, table: "articles") }
          it { is_expected.to articles_sql have_transaction_at(transaction_datetime, table: "articles") }
        end
      end

      context ".left_joins" do
        let(:relation) { Blog.left_joins(:articles) }

        # LEFT OUTER JOIN
        it { is_expected.to blogs_sql scan_once 'LEFT OUTER JOIN "articles"' }
        it { is_expected.to blogs_sql have_valid_at(time_current, table: "articles") }
        it { is_expected.to blogs_sql have_transaction_at(time_current, table: "articles") }
        # WHERE
        it { is_expected.to blogs_sql have_valid_at(time_current, table: "blogs") }
        it { is_expected.to blogs_sql have_transaction_at(time_current, table: "blogs") }
        # load association
        it { is_expected.to articles_sql have_valid_at(time_current, table: "articles") }
        it { is_expected.to articles_sql have_transaction_at(time_current, table: "articles") }

        context "with `ignore_valid_datetime`" do
          let(:relation) { Blog.ignore_valid_datetime.left_joins(:articles) }

          # LEFT OUTER JOIN
          it { is_expected.to blogs_sql scan_once 'LEFT OUTER JOIN "articles"' }
          it { is_expected.to blogs_sql not_have_valid_at(table: "articles") }
          it { is_expected.to blogs_sql have_transaction_at(time_current, table: "articles") }
          # WHERE
          it { is_expected.to blogs_sql not_have_valid_at(table: "blogs") }
          it { is_expected.to blogs_sql have_transaction_at(time_current, table: "blogs") }
          # load association
          it { is_expected.to articles_sql have_valid_at(time_current, table: "articles") }
          it { is_expected.to articles_sql have_transaction_at(time_current, table: "articles") }
        end

        context "with `valid_at`" do
          let(:valid_datetime) { "2019/01/01".in_time_zone }
          let(:relation) { Blog.valid_at(valid_datetime).left_joins(:articles) }

          # INNER JOIN
          it { is_expected.to blogs_sql scan_once 'LEFT OUTER JOIN "articles"' }
          it { is_expected.to blogs_sql have_valid_at(valid_datetime, table: "articles") }
          it { is_expected.to blogs_sql have_transaction_at(time_current, table: "articles") }
          # WHERE
          it { is_expected.to blogs_sql have_valid_at(valid_datetime, table: "blogs") }
          it { is_expected.to blogs_sql have_transaction_at(time_current, table: "blogs") }
          # load association
          it { is_expected.to articles_sql have_valid_at(valid_datetime, table: "articles") }
          it { is_expected.to articles_sql have_transaction_at(time_current, table: "articles") }
        end

        context "with `ignore_transaction_datetime`" do
          let(:relation) { Blog.ignore_transaction_datetime.left_joins(:articles) }

          # LEFT OUTER JOIN
          it { is_expected.to blogs_sql scan_once 'LEFT OUTER JOIN "articles"' }
          it { is_expected.to blogs_sql have_valid_at(time_current, table: "articles") }
          it { is_expected.to blogs_sql not_have_transaction_at(table: "articles") }
          # WHERE
          it { is_expected.to blogs_sql have_valid_at(time_current, table: "blogs") }
          it { is_expected.to blogs_sql not_have_transaction_at(table: "blogs") }
          # load association
          it { is_expected.to articles_sql have_valid_at(time_current, table: "articles") }
          it { is_expected.to articles_sql have_transaction_at(time_current, table: "articles") }
        end

        context "with `transaction_at`" do
          let(:transaction_datetime) { "2019/01/01".in_time_zone }
          let(:relation) { Blog.transaction_at(transaction_datetime).left_joins(:articles) }

          # INNER JOIN
          it { is_expected.to blogs_sql scan_once 'LEFT OUTER JOIN "articles"' }
          it { is_expected.to blogs_sql have_valid_at(time_current, table: "articles") }
          it { is_expected.to blogs_sql have_transaction_at(transaction_datetime, table: "articles") }
          # WHERE
          it { is_expected.to blogs_sql have_valid_at(time_current, table: "blogs") }
          it { is_expected.to blogs_sql have_transaction_at(transaction_datetime, table: "blogs") }
          # load association
          it { is_expected.to articles_sql have_valid_at(time_current, table: "articles") }
          it { is_expected.to articles_sql have_transaction_at(transaction_datetime, table: "articles") }
        end
      end

      context ".preload" do
        let(:relation) { Blog.preload(:articles) }

        # WHERE
        it { is_expected.to blogs_sql have_valid_at(time_current, table: "blogs") }
        it { is_expected.to blogs_sql have_transaction_at(time_current, table: "blogs") }
        # load association
        it { is_expected.to articles_sql have_valid_at(time_current, table: "articles") }
        it { is_expected.to articles_sql have_transaction_at(time_current, table: "articles") }

        context "with `ignore_valid_datetime`" do
          let(:relation) { Blog.ignore_valid_datetime.preload(:articles) }

          # WHERE
          it { is_expected.to blogs_sql not_have_valid_at(table: "blogs") }
          it { is_expected.to blogs_sql have_transaction_at(time_current, table: "blogs") }
          # load association
          it { is_expected.to articles_sql not_have_valid_at(table: "articles") }
          it { is_expected.to articles_sql have_transaction_at(time_current, table: "articles") }
        end

        context "with `valid_at`" do
          let(:valid_datetime) { "2019/01/01".in_time_zone }
          let(:relation) { Blog.valid_at(valid_datetime).preload(:articles) }

          # WHERE
          it { is_expected.to blogs_sql have_valid_at(valid_datetime, table: "blogs") }
          it { is_expected.to blogs_sql have_transaction_at(time_current, table: "blogs") }
          # load association
          it { is_expected.to articles_sql have_valid_at(valid_datetime, table: "articles") }
          it { is_expected.to articles_sql have_transaction_at(time_current, table: "articles") }
        end

        context "with `ignore_transaction_datetime`" do
          let(:relation) { Blog.ignore_transaction_datetime.preload(:articles) }

          # WHERE
          it { is_expected.to blogs_sql have_valid_at(time_current, table: "blogs") }
          it { is_expected.to blogs_sql not_have_transaction_at(table: "blogs") }
          # load association
          it { is_expected.to articles_sql have_valid_at(time_current, table: "articles") }
          it { is_expected.to articles_sql not_have_transaction_at(table: "articles") }
        end

        context "with `transaction_at`" do
          let(:transaction_datetime) { "2019/01/01".in_time_zone }
          let(:relation) { Blog.transaction_at(transaction_datetime).preload(:articles) }

          # WHERE
          it { is_expected.to blogs_sql have_valid_at(time_current, table: "blogs") }
          it { is_expected.to blogs_sql have_transaction_at(transaction_datetime, table: "blogs") }
          # load association
          it { is_expected.to articles_sql have_valid_at(time_current, table: "articles") }
          it { is_expected.to articles_sql have_transaction_at(transaction_datetime, table: "articles") }
        end
      end

      context ".eager_load" do
        define_method(:have_valid_at) { |datetime = Time.current, table:|
               include(%{"#{table}"."valid_from" <= '#{datetime.to_formatted_s(:db)}'})
          .and include(%{"#{table}"."valid_to" > '#{datetime.to_formatted_s(:db)}'})
        }
        define_method(:have_transaction_at) { |datetime, table:|
               include(%{"#{table}"."transaction_from" <= '#{datetime.to_formatted_s(:db)}'})
          .and include(%{"#{table}"."transaction_to" > '#{datetime.to_formatted_s(:db)}'})
        }
        let(:relation) { Blog.eager_load(:articles) }

        # WHERE
        it { is_expected.to blogs_sql have_valid_at(time_current, table: "blogs") }
        it { is_expected.to blogs_sql have_transaction_at(time_current, table: "blogs") }
        # load association
        it { is_expected.to blogs_sql have_valid_at(time_current, table: "articles") }
        it { is_expected.to blogs_sql have_transaction_at(time_current, table: "articles") }

        context "with `ignore_valid_datetime`" do
          define_method(:not_have_valid_at) { |datetime = Time.current, table:|
                 not_scan(%{"#{table}"."valid_from" <= '#{datetime.to_formatted_s(:db)}'})
            .and not_scan(%{"#{table}"."valid_to" > '#{datetime.to_formatted_s(:db)}'})
          }

          let(:relation) { Blog.ignore_valid_datetime.eager_load(:articles) }

          # WHERE
          it { is_expected.to blogs_sql not_have_valid_at(time_current, table: "blogs") }
          it { is_expected.to blogs_sql have_transaction_at(time_current, table: "blogs") }
          # load association
          it { is_expected.to blogs_sql not_have_valid_at(time_current, table: "articles") }
          it { is_expected.to blogs_sql have_transaction_at(time_current, table: "articles") }
        end

        context "with `valid_at`" do
          let(:valid_datetime) { "2019/01/01".in_time_zone }
          let(:relation) { Blog.valid_at(valid_datetime).eager_load(:articles) }

          # WHERE
          it { is_expected.to blogs_sql have_valid_at(valid_datetime, table: "blogs") }
          it { is_expected.to blogs_sql have_transaction_at(time_current, table: "blogs") }
          # load association
          it { is_expected.to blogs_sql have_valid_at(valid_datetime, table: "articles") }
          it { is_expected.to blogs_sql have_transaction_at(time_current, table: "articles") }
        end

        context "with `ignore_transaction_datetime`" do
          define_method(:not_have_transaction_at) { |datetime = Time.current, table:|
                 not_scan(%{"#{table}"."transaction_from" <= '#{datetime.to_formatted_s(:db)}'})
            .and not_scan(%{"#{table}"."transaction_to" > '#{datetime.to_formatted_s(:db)}'})
          }

          let(:relation) { Blog.ignore_transaction_datetime.eager_load(:articles) }

          # WHERE
          it { is_expected.to blogs_sql have_valid_at(time_current, table: "blogs") }
          it { is_expected.to blogs_sql not_have_transaction_at(time_current, table: "blogs") }
          # load association
          it { is_expected.to blogs_sql have_valid_at(time_current, table: "articles") }
          it { is_expected.to blogs_sql not_have_transaction_at(time_current, table: "articles") }
        end

        context "with `transaction_at`" do
          let(:transaction_datetime) { "2019/01/01".in_time_zone }
          let(:relation) { Blog.transaction_at(transaction_datetime).eager_load(:articles) }

          # WHERE
          it { is_expected.to blogs_sql have_valid_at(time_current, table: "blogs") }
          it { is_expected.to blogs_sql have_transaction_at(transaction_datetime, table: "blogs") }
          # load association
          it { is_expected.to blogs_sql have_valid_at(time_current, table: "articles") }
          it { is_expected.to blogs_sql have_transaction_at(transaction_datetime, table: "articles") }
        end
      end
    end

    describe "with `prepared_statements`" do
      let(:sql) { relation.arel.to_sql }

      context "default_scope" do
        let(:relation) { Blog.all }
        it { is_expected.to match %r/"blogs"."transaction_from" <= \$1/ }
        it { is_expected.to match %r/"blogs"."transaction_to" > \$2/ }
        it { is_expected.to match %r/"blogs"."valid_from" <= \$3/ }
        it { is_expected.to match %r/"blogs"."valid_to" > \$4/ }
      end

      context ".valid_at" do
        let(:relation) { Blog.valid_at("2020/01/01") }
        it { is_expected.to match %r/"blogs"."transaction_from" <= \$1/ }
        it { is_expected.to match %r/"blogs"."transaction_to" > \$2/ }
        it { is_expected.to match %r/"blogs"."valid_from" <= \$3/ }
        it { is_expected.to match %r/"blogs"."valid_to" > \$4/ }
      end

      context ".ignore_valid_datetime" do
        let(:relation) { Blog.ignore_valid_datetime }
        it { is_expected.to match %r/"blogs"."transaction_from" <= \$1/ }
        it { is_expected.to match %r/"blogs"."transaction_to" > \$2/ }
        it { is_expected.not_to match %r/"blogs"."valid_from" <= \$3/ }
        it { is_expected.not_to match %r/"blogs"."valid_to" > \$4/ }
      end

      context ".transaction_at" do
        let(:relation) { Blog.transaction_at("2020/01/01") }
        it { is_expected.to match %r/"blogs"."valid_from" <= \$1/ }
        it { is_expected.to match %r/"blogs"."valid_to" > \$2/ }
        it { is_expected.to match %r/"blogs"."transaction_from" <= \$3/ }
        it { is_expected.to match %r/"blogs"."transaction_to" > \$4/ }
      end

      context ".ignore_transaction_datetime" do
        let(:relation) { Blog.ignore_transaction_datetime }
        it { is_expected.not_to match %r/"blogs"."transaction_from" <= \$1/ }
        it { is_expected.not_to match %r/"blogs"."transaction_to" > \$2/ }
        it { is_expected.to match %r/"blogs"."valid_from" <= \$1/ }
        it { is_expected.to match %r/"blogs"."valid_to" > \$2/ }
      end

      context ".bitemporal_at" do
        let(:relation) { Blog.bitemporal_at("2020/01/01") }
        it { is_expected.to match %r/"blogs"."transaction_from" <= \$1/ }
        it { is_expected.to match %r/"blogs"."transaction_to" > \$2/ }
        it { is_expected.to match %r/"blogs"."valid_from" <= \$3/ }
        it { is_expected.to match %r/"blogs"."valid_to" > \$4/ }
      end

      context ".ignore_transaction_datetime" do
        let(:relation) { Blog.ignore_transaction_datetime }
        it { is_expected.not_to match %r/"blogs"."transaction_from" <= \$1/ }
        it { is_expected.not_to match %r/"blogs"."transaction_to" > \$2/ }
        it { is_expected.not_to match %r/"blogs"."valid_from" <= \$3/ }
        it { is_expected.not_to match %r/"blogs"."valid_to" > \$4/ }
      end
    end

    describe ".except_bitemporal_default_scope" do
      let(:sql) { relation.except_bitemporal_default_scope.to_sql }

      context "default_scope" do
        let(:relation) { Blog.all }
        it { is_expected.to not_have_bitemporal_at(table: "blogs") }
      end

      context ".bitemporal_at" do
        let(:relation) { Blog.bitemporal_at(_01_01) }
        it { is_expected.to have_bitemporal_at(_01_01, table: "blogs") }
      end

      context ".bitemporal_at.ignore_bitemporal_datetime" do
        let(:relation) { Blog.bitemporal_at(_01_01).ignore_bitemporal_datetime }
        it { is_expected.to not_have_bitemporal_at(table: "blogs") }
      end

      context ".ignore_bitemporal_datetime" do
        let(:relation) { Blog.ignore_bitemporal_datetime }
        it { is_expected.to not_have_bitemporal_at(table: "blogs") }
      end

      context ".ignore_bitemporal_datetime.bitemporal_at" do
        let(:relation) { Blog.ignore_bitemporal_datetime.bitemporal_at(_01_01) }
        it { is_expected.to have_bitemporal_at(_01_01, table: "blogs") }
      end

      context ".valid_at" do
        let(:relation) { Blog.valid_at(_01_01) }
        it { is_expected.to have_valid_at(_01_01, table: "blogs") }
        it { is_expected.to not_have_transaction_at(table: "blogs") }
      end

      context ".valid_at.ignore_bitemporal_datetime" do
        let(:relation) { Blog.valid_at(_01_01).ignore_bitemporal_datetime }
        it { is_expected.to not_have_valid_at(table: "blogs") }
        it { is_expected.to not_have_transaction_at(table: "blogs") }
      end

      context ".ignore_valid_datetime" do
        let(:relation) { Blog.ignore_valid_datetime }
        it { is_expected.to not_have_valid_at(table: "blogs") }
        it { is_expected.to not_have_transaction_at(table: "blogs") }
      end

      context ".ignore_valid_datetime.valid_at" do
        let(:relation) { Blog.ignore_valid_datetime.valid_at(_01_01) }
        it { is_expected.to have_valid_at(_01_01, table: "blogs") }
        it { is_expected.to not_have_transaction_at(table: "blogs") }
      end

      context "ActiveRecord::Bitemporal.valid_at" do
        let(:relation) { ActiveRecord::Bitemporal.valid_at(_01_01) { Blog.all } }
        it { is_expected.to not_have_valid_at(table: "blogs") }
        it { is_expected.to not_have_transaction_at(table: "blogs") }
      end

      context ".transaction_at" do
        let(:relation) { Blog.transaction_at(_01_01) }
        it { is_expected.to not_have_valid_at(table: "blogs") }
        it { is_expected.to have_transaction_at(_01_01, table: "blogs") }
      end

      context ".transaction_at.ignore_bitemporal_datetime" do
        let(:relation) { Blog.transaction_at(_01_01).ignore_bitemporal_datetime }
        it { is_expected.to not_have_valid_at(table: "blogs") }
        it { is_expected.to not_have_transaction_at(table: "blogs") }
      end

      context ".ignore_transaction_datetime" do
        let(:relation) { Blog.ignore_transaction_datetime }
        it { is_expected.to not_have_valid_at(table: "blogs") }
        it { is_expected.to not_have_transaction_at(table: "blogs") }
      end

      context ".ignore_transaction_datetime.transaction_at" do
        let(:relation) { Blog.ignore_transaction_datetime.transaction_at(_01_01) }
        it { is_expected.to not_have_valid_at(table: "blogs") }
        it { is_expected.to have_transaction_at(_01_01, table: "blogs") }
      end

    end
  end

  describe "bitemporal_option" do
    let(:time_current) { Time.current.round }
    let(:bitemporal_option) { relation.bitemporal_option }
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

    context "ActiveRecord::Bitemporal.valid_at" do
      let(:valid_datetime) { "2019/01/1".in_time_zone }
      let(:relation) { ActiveRecord::Bitemporal.valid_at(valid_datetime) { Blog.all } }
      it { is_expected.to include(valid_datetime: valid_datetime, transaction_datetime: time_current) }

      context ".valid_at" do
        let(:valid_datetime) { "2019/01/1".in_time_zone }
        let(:relation) { ActiveRecord::Bitemporal.valid_at("1999/01/01") { Blog.valid_at(valid_datetime) } }
        it { is_expected.to include(valid_datetime: valid_datetime, transaction_datetime: time_current) }
      end
    end

    context "ActiveRecord::Bitemporal.valid_at!" do
      let(:valid_datetime) { "2019/01/1".in_time_zone }
      let(:relation) { ActiveRecord::Bitemporal.valid_at!(valid_datetime) { Blog.all } }
      it { is_expected.to include(valid_datetime: valid_datetime, transaction_datetime: time_current) }

      context ".valid_at" do
        let(:valid_datetime) { "2019/01/1".in_time_zone }
        let(:relation) { ActiveRecord::Bitemporal.valid_at!(valid_datetime) { Blog.valid_at("1999/01/01") } }
        it { is_expected.to include(valid_datetime: valid_datetime, transaction_datetime: time_current) }
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

    context "ActiveRecord::Bitemporal.transaction_at" do
      let(:transaction_datetime) { "2019/01/1".in_time_zone }
      let(:relation) { ActiveRecord::Bitemporal.transaction_at(transaction_datetime) { Blog.all } }
      it { is_expected.to include(valid_datetime: time_current, transaction_datetime: transaction_datetime) }

      context ".transaction_at" do
        let(:transaction_datetime) { "2019/01/1".in_time_zone }
        let(:relation) { ActiveRecord::Bitemporal.transaction_at("1999/01/01") { Blog.transaction_at(transaction_datetime) } }
        it { is_expected.to include(valid_datetime: time_current, transaction_datetime: transaction_datetime) }
      end
    end

    context "ActiveRecord::Bitemporal.transaction_at!" do
      let(:transaction_datetime) { "2019/01/1".in_time_zone }
      let(:relation) { ActiveRecord::Bitemporal.transaction_at!(transaction_datetime) { Blog.all } }
      it { is_expected.to include(valid_datetime: time_current, transaction_datetime: transaction_datetime) }

      context ".transaction_at" do
        let(:transaction_datetime) { "2019/01/1".in_time_zone }
        let(:relation) { ActiveRecord::Bitemporal.transaction_at!(transaction_datetime) { Blog.transaction_at("1999/01/01") } }
        it { is_expected.to include(valid_datetime: time_current, transaction_datetime: transaction_datetime) }
      end
    end

    context "with `.ignore_transaction_datetime`" do
      let(:relation) { Blog.ignore_transaction_datetime }
      it { is_expected.to include(valid_datetime: time_current) }
      it { is_expected.not_to include(transaction_datetime: time_current) }
    end

    context "with Arel::Nodes::SqlLiteral" do
      let(:relation) { Blog.where(Blog.arel_table[:valid_to].gt(Arel::Nodes::SqlLiteral.new(1.days.to_s))) }
      it { is_expected.to include(valid_from: time_current, valid_to: nil) }
    end

    describe "record#bitemporal_option" do
      let!(:blog) { Blog.create(valid_from: "1999/01/01", transaction_from: "1999/01/01") }
      let(:record) { relation.first }
      let(:bitemporal_option) { record.bitemporal_option  }
      subject { Timecop.freeze(time_current) { bitemporal_option } }

      context "default_scope" do
        let(:relation) { Blog.all }
        it { is_expected.not_to include(:valid_datetime) }
      end

      context ".valid_at" do
        let(:valid_datetime) { "2019/01/1".in_time_zone }
        let(:relation) { Blog.valid_at(valid_datetime) }
        it { is_expected.to include(valid_datetime: valid_datetime) }
      end

      context "#valid_at" do
        let(:valid_datetime) { "2019/01/1".in_time_zone }
        let(:relation) { Blog.all }
        let(:bitemporal_option) { Timecop.freeze(time_current) { record.valid_at(valid_datetime) { |it| it.bitemporal_option } } }
        it { is_expected.to include(valid_datetime: valid_datetime) }
      end

      context ".find_at_time" do
        let(:valid_datetime) { "2019/01/1".in_time_zone }
        let(:record) { Blog.find_at_time(valid_datetime, blog.id) }
        it { is_expected.to include(valid_datetime: valid_datetime) }
      end

      context "ActiveRecord::Bitemporal.valid_at" do
        let(:valid_datetime) { "2019/01/1".in_time_zone }

        context "around get relation" do
          let(:relation) { ActiveRecord::Bitemporal.valid_at(valid_datetime) { Blog.all } }
          it { is_expected.to include(valid_datetime: valid_datetime) }

          context "in .valid_at" do
            let(:bitemporal_valid_datetime) { "2019/05/1".in_time_zone }
            let(:valid_datetime) { "2019/01/1".in_time_zone }
            let(:relation) { ActiveRecord::Bitemporal.valid_at(bitemporal_valid_datetime) { Blog.valid_at(valid_datetime) } }
            it { is_expected.to include(valid_datetime: valid_datetime) }
          end

          context "outside .valid_at" do
            let(:bitemporal_valid_datetime) { "2019/05/1".in_time_zone }
            let(:valid_datetime) { "2019/01/1".in_time_zone }
            let(:relation) { ActiveRecord::Bitemporal.valid_at(bitemporal_valid_datetime) { Blog.all }.valid_at(valid_datetime) }
            it { is_expected.to include(valid_datetime: valid_datetime) }
          end
        end

        context "around get record" do
          let(:record) { ActiveRecord::Bitemporal.valid_at(valid_datetime) { Blog.all.first } }
          it { is_expected.to include(valid_datetime: valid_datetime) }
        end

        context "around get bitemporal_option" do
          let(:bitemporal_option) { ActiveRecord::Bitemporal.valid_at(valid_datetime) { Blog.all.first.bitemporal_option } }
          it { is_expected.to include(valid_datetime: valid_datetime) }
        end
      end

      context "ActiveRecord::Bitemporal.valid_at!" do
        let(:valid_datetime) { "2019/01/1".in_time_zone }

        context "around get relation" do
          let(:relation) { ActiveRecord::Bitemporal.valid_at!(valid_datetime) { Blog.all } }
          it { is_expected.to include(valid_datetime: valid_datetime) }

          context "in .valid_at" do
            let(:bitemporal_valid_datetime) { "2019/05/1".in_time_zone }
            let(:valid_datetime) { "2019/01/1".in_time_zone }
            let(:relation) { ActiveRecord::Bitemporal.valid_at!(bitemporal_valid_datetime) { Blog.valid_at(valid_datetime) } }
            it { is_expected.to include(valid_datetime: bitemporal_valid_datetime) }
          end

          context "outside .valid_at" do
            let(:bitemporal_valid_datetime) { "2019/05/1".in_time_zone }
            let(:valid_datetime) { "2019/01/1".in_time_zone }
            let(:relation) { ActiveRecord::Bitemporal.valid_at!(bitemporal_valid_datetime) { Blog.all }.valid_at(valid_datetime) }
            it { is_expected.to include(valid_datetime: valid_datetime) }
          end
        end

        context "around get record" do
          let(:record) { ActiveRecord::Bitemporal.valid_at!(valid_datetime) { Blog.all.first } }
          it { is_expected.to include(valid_datetime: valid_datetime) }
        end

        context "around get bitemporal_option" do
          let(:bitemporal_option) { ActiveRecord::Bitemporal.valid_at!(valid_datetime) { Blog.all.first.bitemporal_option } }
          it { is_expected.to include(valid_datetime: valid_datetime) }
        end
      end

      context ".transaction_at" do
        let(:transaction_datetime) { "2019/01/1".in_time_zone }
        let(:relation) { Blog.transaction_at(transaction_datetime) }
        it { is_expected.to include(transaction_datetime: transaction_datetime) }
      end

      context "#transaction_at" do
        let(:transaction_datetime) { "2019/01/1".in_time_zone }
        let(:relation) { Blog.all }
        let(:bitemporal_option) { Timecop.freeze(time_current) { record.transaction_at(transaction_datetime) { |it| it.bitemporal_option } } }
        it { is_expected.to include(transaction_datetime: transaction_datetime) }
      end

      describe "association" do
        let!(:blog) { Blog.create(valid_from: "1999/01/01", transaction_from: "1999/01/01") }
        let!(:article) { blog.articles.create(valid_from: "1999/01/01", transaction_from: "1999/01/01") }
        let(:record) { relation.first }
        let(:bitemporal_option) { Timecop.freeze(time_current) { record.bitemporal_option } }
        subject { Timecop.freeze(time_current) { bitemporal_option } }

        context "default_scope" do
          let(:relation) { Blog.all.first.articles }
          it { is_expected.not_to include(:valid_datetime) }
        end

        context "owner.valid_at" do
          let(:valid_datetime) { "2019/01/1".in_time_zone }
          let(:owner) { Blog.valid_at(valid_datetime).first }
          let(:relation) { owner.articles }
          it { is_expected.to include(valid_datetime: valid_datetime) }

          context "with association.valid_at" do
            let(:association_valid_datetime) { "2019/05/1".in_time_zone }
            let(:relation) { owner.articles.valid_at(association_valid_datetime) }
            it { is_expected.to include(valid_datetime: association_valid_datetime) }
          end
        end

        context "association.valid_at" do
          let(:valid_datetime) { "2019/01/1".in_time_zone }
          let(:relation) { Blog.all.first.articles.valid_at(valid_datetime) }
          it { is_expected.to include(valid_datetime: valid_datetime) }
        end

        context "owner.transaction_at" do
          let(:transaction_datetime) { "2019/01/1".in_time_zone }
          let(:owner) { Blog.transaction_at(transaction_datetime).first }
          let(:relation) { owner.articles }
          it { is_expected.to include(transaction_datetime: transaction_datetime) }

          context "with association.transaction_at" do
            let(:association_transaction_datetime) { "2019/05/1".in_time_zone }
            let(:relation) { owner.articles.transaction_at(association_transaction_datetime) }
            it { is_expected.to include(transaction_datetime: association_transaction_datetime) }
          end
        end

        context "association.transaction_at" do
          let(:transaction_datetime) { "2019/01/1".in_time_zone }
          let(:relation) { Blog.all.first.articles.transaction_at(transaction_datetime) }
          it { is_expected.to include(transaction_datetime: transaction_datetime) }
        end
      end
    end

    describe ".or" do
      let(:relation) { Blog.where(name: "Homu").or(Blog.where(name: "Mami")) }
      it { is_expected.to include(valid_datetime: time_current, ignore_valid_datetime: false) }

      context ".valid_at.or(...)" do
        let(:datetime) { "2019/01/1".in_time_zone }
        let(:relation) { Blog.valid_at(datetime).where(name: "Homu").or(Blog.where(name: "Mami")) }
        it { is_expected.to include(valid_datetime: time_current, ignore_valid_datetime: false) }
      end

      context ".or(valid_at)" do
        let(:datetime) { "2019/01/1".in_time_zone }
        let(:relation) { Blog.where(name: "Homu").or(Blog.valid_at(datetime).where(name: "Mami")) }
        it { is_expected.to include(valid_datetime: datetime, ignore_valid_datetime: false) }
      end

      context ".valid_at.or(valid_at)" do
        let(:datetime1) { "2019/05/1".in_time_zone }
        let(:datetime2) { "2019/01/1".in_time_zone }
        let(:relation) { Blog.valid_at(datetime1).where(name: "Homu").or(Blog.valid_at(datetime2).where(name: "Mami")) }
        it { is_expected.to include(valid_datetime: datetime2, ignore_valid_datetime: false) }
      end

      context ".transaction_at.or(valid_at)" do
        let(:datetime1) { "2019/05/1".in_time_zone }
        let(:datetime2) { "2019/01/1".in_time_zone }
        let(:relation) { Blog.transaction_at(datetime1).where(name: "Homu").or(Blog.transaction_at(datetime2).where(name: "Mami")) }
      end

      context ".ignore_valid_datetime.or(...)" do
        let(:relation) { Blog.ignore_valid_datetime.where(name: "Homu").or(Blog.where(name: "Mami")) }
        it { is_expected.to include(valid_datetime: time_current, ignore_valid_datetime: false) }
      end

      context ".or(ignore_valid_datetime)" do
        let(:relation) { Blog.where(name: "Homu").or(Blog.ignore_valid_datetime.where(name: "Mami")) }
        it { is_expected.to include(valid_datetime: time_current, ignore_valid_datetime: false) }
      end

      context ".ignore_valid_datetime.or(ignore_valid_datetime)" do
        let(:relation) { Blog.ignore_valid_datetime.where(name: "Homu").or(Blog.ignore_valid_datetime.where(name: "Mami")) }
        it { is_expected.to include(valid_datetime: nil, ignore_valid_datetime: true) }
      end

      context "where with String" do
        let(:relation) { Blog.where('name = "Homu"').or(Blog.where('name = "Mami"')) }
        it { is_expected.to include(valid_datetime: time_current, ignore_valid_datetime: false) }
      end
    end
  end

  describe ".with_valid_datetime" do
    subject { relation.bitemporal_value[:with_valid_datetime] }

    context "default scope" do
      let(:relation) { Blog.all }
      it { is_expected.to eq :default_scope }
    end

    context "with .valid_at" do
      let(:relation) { Blog.valid_at("04/01") }
      it { is_expected.to be_truthy }
    end

    context "with .ignore_valid_datetime" do
      let(:relation) { Blog.ignore_valid_datetime }
      it { is_expected.to be_falsey }
    end

    context "with valid_at.ignore_valid_datetime" do
      let(:relation) { Blog.valid_at("04/01").ignore_valid_datetime }
      it { is_expected.to be_falsey }
    end

    context "with ignore_valid_datetime.valid_at" do
      let(:relation) { Blog.ignore_valid_datetime.valid_at("04/01") }
      it { is_expected.to be_truthy }
    end

    context "with ActiveRecord::Bitemporal.valid_at" do
      let(:relation) { ActiveRecord::Bitemporal.valid_at("04/01") { Blog.all } }
      it { is_expected.to eq :default_scope_with_valid_datetime }
    end

    context "with ActiveRecord::Bitemporal.ignore_valid_datetime" do
      let(:relation) { ActiveRecord::Bitemporal.ignore_valid_datetime { Blog.all } }
      it { is_expected.to be_falsey }
    end

    context "with ActiveRecord::Bitemporal.valid_at -> .ignore_valid_datetime" do
      let(:relation) { ActiveRecord::Bitemporal.valid_at("04/01") { Blog.ignore_valid_datetime } }
      it { is_expected.to be_falsey }
    end

    context "with ActiveRecord::Bitemporal.valid_at -> ActiveRecord::Bitemporal.ignore_valid_datetime" do
      let(:relation) { ActiveRecord::Bitemporal.valid_at("04/01") { ActiveRecord::Bitemporal.ignore_valid_datetime { Blog.all } } }
      it { is_expected.to be_falsey }
    end

    context "with ActiveRecord::Bitemporal.ignore_valid_datetime -> .valid_at" do
      let(:relation) { ActiveRecord::Bitemporal.ignore_valid_datetime { Blog.valid_at("04/01") } }
      it { is_expected.to be_truthy }
    end

    context "with ActiveRecord::Bitemporal.ignore_valid_datetime -> ActiveRecord::Bitemporal.valid_at" do
      let(:relation) { ActiveRecord::Bitemporal.ignore_valid_datetime { ActiveRecord::Bitemporal.valid_at("04/01") { Blog.all } } }
      it { is_expected.to be_truthy }
    end

    context "create association when after record loaded" do
      let!(:blog) { Blog.create; Blog.first }
      it { expect { Article.create(blog_id: blog.id) }.to change { blog.articles.count }.by(1) }
    end

    context ".except_valid_datetime" do
      let(:relation) { Blog.all.except_valid_datetime }
      it { expect(relation.bitemporal_value).not_to include(:with_valid_datetime) }
    end

    context ".ignore_valid_datetime.except_valid_datetime" do
      let(:relation) { Blog.ignore_valid_datetime.except_valid_datetime }
      it { expect(relation.bitemporal_value).not_to include(:with_valid_datetime) }
    end

    context ".except_valid_datetime.ignore_valid_datetime" do
      let(:relation) { Blog.except_valid_datetime.ignore_valid_datetime }
      it { expect(relation.bitemporal_value).to include(with_valid_datetime: false) }
    end

    context ".valid_at" do
      let(:relation) { Blog.valid_at("2020/10/01") }
      it { expect(relation.bitemporal_value).to include(with_valid_datetime: true) }
    end

    xcontext ".valid_at.except_valid_datetime" do
      let(:relation) { Blog.valid_at("2020/10/01").except_valid_datetime }
      it { expect(relation.bitemporal_value).to include(with_valid_datetime: true) }
    end

    context ".merge(.)" do
      let(:relation) { Blog.all.merge(User.all) }
      it { expect(relation.bitemporal_value).to include(with_valid_datetime: :default_scope) }
    end

    context ".merge(.valid_at)" do
      let(:relation) { Blog.all.merge(User.valid_at("2020/01/01")) }
      it { expect(relation.bitemporal_value).to include(with_valid_datetime: true) }
    end

    context ".merge(.ignore_valid_datetime)" do
      let(:relation) { Blog.all.merge(User.ignore_valid_datetime) }
      it { expect(relation.bitemporal_value).to include(with_valid_datetime: false) }
    end

    context ".merge(.except_valid_datetime)" do
      let(:relation) { Blog.all.merge(User.except_valid_datetime) }
      it { expect(relation.bitemporal_value).to include(with_valid_datetime: :default_scope) }
    end

    context ".valid_at.merge(.)" do
      let(:relation) { Blog.valid_at("2020/10/01").merge(User.all) }
      it { expect(relation.bitemporal_value).to include(with_valid_datetime: :default_scope) }
    end

    context ".valid_at.merge(.valid_at)" do
      let(:relation) { Blog.valid_at("2020/10/01").merge(User.valid_at("2020/01/01")) }
      it { expect(relation.bitemporal_value).to include(with_valid_datetime: true) }
    end

    context ".valid_at.merge(.ignore_valid_datetime)" do
      let(:relation) { Blog.valid_at("2020/10/01").merge(User.ignore_valid_datetime) }
      it { expect(relation.bitemporal_value).to include(with_valid_datetime: false) }
    end

    context ".valid_at.merge(.except_valid_datetime)" do
      let(:relation) { Blog.valid_at("2020/10/01").merge(User.except_valid_datetime) }
      it { expect(relation.bitemporal_value).to include(with_valid_datetime: true) }
    end

    context ".ignore_valid_datetime.merge(.)" do
      let(:relation) { Blog.ignore_valid_datetime.merge(User.all) }
      it { expect(relation.bitemporal_value).to include(with_valid_datetime: :default_scope) }
    end

    context ".ignore_valid_datetime.merge(.valid_at)" do
      let(:relation) { Blog.ignore_valid_datetime.merge(User.valid_at("2020/01/01")) }
      it { expect(relation.bitemporal_value).to include(with_valid_datetime: true) }
    end

    context ".ignore_valid_datetime.merge(.ignore_valid_datetime)" do
      let(:relation) { Blog.ignore_valid_datetime.merge(User.ignore_valid_datetime) }
      it { expect(relation.bitemporal_value).to include(with_valid_datetime: false) }
    end

    context ".ignore_valid_datetime.merge(.except_valid_datetime)" do
      let(:relation) { Blog.ignore_valid_datetime.merge(User.except_valid_datetime) }
      it { expect(relation.bitemporal_value).to include(with_valid_datetime: false) }
    end

    context ".except_valid_datetime.merge(.)" do
      let(:relation) { Blog.except_valid_datetime.merge(User.all) }
      it { expect(relation.bitemporal_value).to include(with_valid_datetime: :default_scope) }
    end

    context ".except_valid_datetime.merge(.valid_at)" do
      let(:relation) { Blog.except_valid_datetime.merge(User.valid_at("2020/01/01")) }
      it { expect(relation.bitemporal_value).to include(with_valid_datetime: true) }
    end

    context ".except_valid_datetime.merge(.ignore_valid_datetime)" do
      let(:relation) { Blog.except_valid_datetime.merge(User.ignore_valid_datetime) }
      it { expect(relation.bitemporal_value).to include(with_valid_datetime: false) }
    end

    context ".except_valid_datetime.merge(.except_valid_datetime)" do
      let(:relation) { Blog.except_valid_datetime.merge(User.except_valid_datetime) }
      it { expect(relation.bitemporal_value).not_to include(:with_valid_datetime) }
    end
  end

  describe ".with_transaction_datetime" do
    subject { relation.bitemporal_value[:with_transaction_datetime] }

    context "default scope" do
      let(:relation) { Blog.all }
      it { is_expected.to eq :default_scope }
    end

    context "with .transaction_at" do
      let(:relation) { Blog.transaction_at("04/01") }
      it { is_expected.to be_truthy }
    end

    context "with .ignore_transaction_datetime" do
      let(:relation) { Blog.ignore_transaction_datetime }
      it { is_expected.to be_falsey }
    end

    context "with transaction_at.ignore_transaction_datetime" do
      let(:relation) { Blog.transaction_at("04/01").ignore_transaction_datetime }
      it { is_expected.to be_falsey }
    end

    context "with ignore_transaction_datetime.transaction_at" do
      let(:relation) { Blog.ignore_transaction_datetime.transaction_at("04/01") }
      it { is_expected.to be_truthy }
    end

    context "with ActiveRecord::Bitemporal.transaction_at" do
      let(:relation) { ActiveRecord::Bitemporal.transaction_at("04/01") { Blog.all } }
      it { is_expected.to eq :default_scope_with_transaction_datetime }
    end

    context "with ActiveRecord::Bitemporal.ignore_transaction_datetime" do
      let(:relation) { ActiveRecord::Bitemporal.ignore_transaction_datetime { Blog.all } }
      it { is_expected.to be_falsey }
    end

    context "with ActiveRecord::Bitemporal.transaction_at -> .ignore_transaction_datetime" do
      let(:relation) { ActiveRecord::Bitemporal.transaction_at("04/01") { Blog.ignore_transaction_datetime } }
      it { is_expected.to be_falsey }
    end

    context "with ActiveRecord::Bitemporal.transaction_at -> ActiveRecord::Bitemporal.ignore_transaction_datetime" do
      let(:relation) { ActiveRecord::Bitemporal.transaction_at("04/01") { ActiveRecord::Bitemporal.ignore_transaction_datetime { Blog.all } } }
      it { is_expected.to be_falsey }
    end

    context "with ActiveRecord::Bitemporal.ignore_transaction_datetime -> .transaction_at" do
      let(:relation) { ActiveRecord::Bitemporal.ignore_transaction_datetime { Blog.transaction_at("04/01") } }
      it { is_expected.to be_truthy }
    end

    context "with ActiveRecord::Bitemporal.ignore_transaction_datetime -> ActiveRecord::Bitemporal.transaction_at" do
      let(:relation) { ActiveRecord::Bitemporal.ignore_transaction_datetime { ActiveRecord::Bitemporal.transaction_at("04/01") { Blog.all } } }
      it { is_expected.to be_truthy }
    end

    context "create association when after record loaded" do
      let!(:blog) { Blog.create; Blog.first }
      it { expect { Article.create(blog_id: blog.id) }.to change { blog.articles.count }.by(1) }
    end

    context ".except_transaction_datetime" do
      let(:relation) { Blog.all.except_transaction_datetime }
      it { expect(relation.bitemporal_value).not_to include(:with_transaction_datetime) }
    end

    context ".ignore_transaction_datetime.except_transaction_datetime" do
      let(:relation) { Blog.ignore_transaction_datetime.except_transaction_datetime }
      it { expect(relation.bitemporal_value).not_to include(:with_transaction_datetime) }
    end

    context ".except_transaction_datetime.ignore_transaction_datetime" do
      let(:relation) { Blog.except_transaction_datetime.ignore_transaction_datetime }
      it { expect(relation.bitemporal_value).to include(with_transaction_datetime: false) }
    end

    context ".transaction_at" do
      let(:relation) { Blog.transaction_at("2020/10/01") }
      it { expect(relation.bitemporal_value).to include(with_transaction_datetime: true) }
    end

    xcontext ".transaction_at.except_transaction_datetime" do
      let(:relation) { Blog.transaction_at("2020/10/01").except_transaction_datetime }
      it { expect(relation.bitemporal_value).to include(with_transaction_datetime: true) }
    end

    context ".merge(.)" do
      let(:relation) { Blog.all.merge(User.all) }
      it { expect(relation.bitemporal_value).to include(with_transaction_datetime: :default_scope) }
    end

    context ".merge(.transaction_at)" do
      let(:relation) { Blog.all.merge(User.transaction_at("2020/01/01")) }
      it { expect(relation.bitemporal_value).to include(with_transaction_datetime: true) }
    end

    context ".merge(.ignore_transaction_datetime)" do
      let(:relation) { Blog.all.merge(User.ignore_transaction_datetime) }
      it { expect(relation.bitemporal_value).to include(with_transaction_datetime: false) }
    end

    context ".merge(.except_transaction_datetime)" do
      let(:relation) { Blog.all.merge(User.except_transaction_datetime) }
      it { expect(relation.bitemporal_value).to include(with_transaction_datetime: :default_scope) }
    end

    context ".transaction_at.merge(.)" do
      let(:relation) { Blog.transaction_at("2020/10/01").merge(User.all) }
      it { expect(relation.bitemporal_value).to include(with_transaction_datetime: :default_scope) }
    end

    context ".transaction_at.merge(.transaction_at)" do
      let(:relation) { Blog.transaction_at("2020/10/01").merge(User.transaction_at("2020/01/01")) }
      it { expect(relation.bitemporal_value).to include(with_transaction_datetime: true) }
    end

    context ".transaction_at.merge(.ignore_transaction_datetime)" do
      let(:relation) { Blog.transaction_at("2020/10/01").merge(User.ignore_transaction_datetime) }
      it { expect(relation.bitemporal_value).to include(with_transaction_datetime: false) }
    end

    context ".transaction_at.merge(.except_transaction_datetime)" do
      let(:relation) { Blog.transaction_at("2020/10/01").merge(User.except_transaction_datetime) }
      it { expect(relation.bitemporal_value).to include(with_transaction_datetime: true) }
    end

    context ".ignore_transaction_datetime.merge(.)" do
      let(:relation) { Blog.ignore_transaction_datetime.merge(User.all) }
      it { expect(relation.bitemporal_value).to include(with_transaction_datetime: :default_scope) }
    end

    context ".ignore_transaction_datetime.merge(.transaction_at)" do
      let(:relation) { Blog.ignore_transaction_datetime.merge(User.transaction_at("2020/01/01")) }
      it { expect(relation.bitemporal_value).to include(with_transaction_datetime: true) }
    end

    context ".ignore_transaction_datetime.merge(.ignore_transaction_datetime)" do
      let(:relation) { Blog.ignore_transaction_datetime.merge(User.ignore_transaction_datetime) }
      it { expect(relation.bitemporal_value).to include(with_transaction_datetime: false) }
    end

    context ".ignore_transaction_datetime.merge(.except_transaction_datetime)" do
      let(:relation) { Blog.ignore_transaction_datetime.merge(User.except_transaction_datetime) }
      it { expect(relation.bitemporal_value).to include(with_transaction_datetime: false) }
    end

    context ".except_transaction_datetime.merge(.)" do
      let(:relation) { Blog.except_transaction_datetime.merge(User.all) }
      it { expect(relation.bitemporal_value).to include(with_transaction_datetime: :default_scope) }
    end

    context ".except_transaction_datetime.merge(.transaction_at)" do
      let(:relation) { Blog.except_transaction_datetime.merge(User.transaction_at("2020/01/01")) }
      it { expect(relation.bitemporal_value).to include(with_transaction_datetime: true) }
    end

    context ".except_transaction_datetime.merge(.ignore_transaction_datetime)" do
      let(:relation) { Blog.except_transaction_datetime.merge(User.ignore_transaction_datetime) }
      it { expect(relation.bitemporal_value).to include(with_transaction_datetime: false) }
    end

    context ".except_transaction_datetime.merge(.except_transaction_datetime)" do
      let(:relation) { Blog.except_transaction_datetime.merge(User.except_transaction_datetime) }
      it { expect(relation.bitemporal_value).not_to include(:with_transaction_datetime) }
    end
  end
end
