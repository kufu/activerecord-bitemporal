ActiveRecord::Bitemporal
========================

[![License](https://img.shields.io/github/license/kufu/activerecord-bitemporal.svg?color=blue)](https://github.com/kufu/activerecord-bitemporal/blob/master/LICENSE)
[![gem-version](https://img.shields.io/gem/v/activerecord-bitemporal.svg)](https://rubygems.org/gems/activerecord-bitemporal)
[![gem-download](https://img.shields.io/gem/dt/activerecord-bitemporal.svg)](https://rubygems.org/gems/activerecord-bitemporal)
[![CircleCI](https://circleci.com/gh/kufu/activerecord-bitemporal.svg?style=svg)](https://circleci.com/gh/kufu/activerecord-bitemporal)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'activerecord-bitemporal'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install activerecord-bitemporal

## 概要

activerecord-bitemporal は Rails の ActiveRecord で Bitemporal Data Model を扱うためのライブラリになります。
activerecord-bitemporal では、モデルを生成すると

```ruby
employee = nil
# MEMO: データをわかりやすくする為に時間を固定
#       2019/1/10 にレコードを生成する
Timecop.freeze("2019/1/10") {
  employee = Employee.create(emp_code: "001", name: "Jane")
}
```

以下のようなレコードが生成されます。

| id | bitemporal_id | emp_code | name | valid_from | valid_to | transaction_from | transaction_to |
|  --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | 001 | Jane | 2019-01-10 | 9999-12-31 | 2019-01-10 | 9999-12-31 |

そのモデルに対して更新を行うと

```ruby
employee = nil
Timecop.freeze("2019/1/10") {
  employee = Employee.create(emp_code: "001", name: "Jane")
}

Timecop.freeze("2019/1/15") {
  # 更新する
  employee.update(name: "Tom")
}
```

次のような履歴レコードが暗黙的に生成されます。

| id | bitemporal_id | emp_code | name | valid_from | valid_to | transaction_from | transaction_to |
|  --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | 001 | Jane | 2019-01-10 | 9999-12-31 | 2019-01-10 | 2019-01-15 |
| 2 | 1 | 001 | Jane | 2019-01-10 | 2019-01-15 | 2019-01-15 | 9999-12-31 |
| 3 | 1 | 001 | Tom | 2019-01-15 | 9999-12-31 | 2019-01-15 | 9999-12-31 |

更に更新すると

```ruby
employee = nil
Timecop.freeze("2019/1/10") {
  employee = Employee.create(emp_code: "001", name: "Jane")
}

Timecop.freeze("2019/1/15") {
  employee.update(name: "Tom")
}

Timecop.freeze("2019/1/20") {
  # 更に更新
  employee.update(name: "Kevin")
}
```

更新する度にどんどん履歴レコードが増えていきます。

| id | bitemporal_id | emp_code | name | valid_from | valid_to | transaction_from | transaction_to |
|  --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | 001 | Jane | 2019-01-10 | 9999-12-31 | 2019-01-10 | 2019-01-15 |
| 2 | 1 | 001 | Jane | 2019-01-10 | 2019-01-15 | 2019-01-15 | 9999-12-31 |
| 3 | 1 | 001 | Tom | 2019-01-15 | 9999-12-31 | 2019-01-15 | 2019-01-20 |
| 4 | 1 | 001 | Tom | 2019-01-15 | 2019-01-20 | 2019-01-20 | 9999-12-31 |
| 5 | 1 | 001 | Kevin | 2019-01-20 | 9999-12-31 | 2019-01-20 | 9999-12-31 |

また、レコードを読み込む場合は暗黙的に『一番最新のレコード』を参照します。

```ruby
employee = nil
Timecop.freeze("2019/1/10") {
  employee = Employee.create(emp_code: "001", name: "Jane")
}

Timecop.freeze("2019/1/15") {
  employee.update(name: "Tom")
}

Timecop.freeze("2019/1/20") {
  employee.update(name: "Kevin")
}

Timecop.freeze("2019/1/25") {
  # 現時点で有効なレコードのみを参照する
  pp Employee.count
  # => 1

  # name = "Tom" は過去の履歴レコードとして扱われるので参照されない
  pp Employee.find_by(name: "Tom")
  # => nil

  # 最新のみ参照する
  pp Employee.all
  # [#<Employee:0x0000559b1b37eb08
  #   id: 1,
  #   bitemporal_id: 1,
  #   emp_code: "001",
  #   name: "Kevin",
  #   valid_from: 2019-01-20,
  #   valid_to: 9999-12-31,
  #   transaction_from: 2019-01-20,
  #   transaction_to: 9999-12-31>]
}
```

任意の時間の履歴レコードを参照したい場合は `find_at_time(datetime, id)` で時間指定して取得する事が出来ます。

```ruby
employee = nil
Timecop.freeze("2019/1/10") {
  employee = Employee.create(emp_code: "001", name: "Jane")
}

Timecop.freeze("2019/1/15") {
  employee.update(name: "Tom")
}

Timecop.freeze("2019/1/20") {
  employee.update(name: "Kevin")
}

# 2019/1/25 に固定
Timecop.freeze("2019/1/25") {
  # 任意の時間の履歴レコードを取得する
  pp Employee.find_at_time("2019/1/13", employee.id).name
  # => "Jane"
  pp Employee.find_at_time("2019/1/18", employee.id).name
  # => "Tom"
  pp Employee.find_at_time("2019/1/23", employee.id).name
  # => "Kevin"
}
```

このように activerecord-bitemporal は、

* 保存時に履歴レコードを自動生成
* `.find_at_time` 等で任意の時間のレコードを取得する

というような事を行うライブラリになります。


## モデルを BiTemporal Data Model 化する

任意のモデルを BiTemporal Data Model(以下、BTDM)として扱う場合は、以下のカラムを DB に追加する必要があります。

```ruby
ActiveRecord::Schema.define(version: 1) do
  create_table :employees, force: true do |t|
    t.string :emp_code
    t.string :name

    # BTDM に必要なカラムを追加する
    t.integer :bitemporal_id
    t.datetime :valid_from
    t.datetime :valid_to
    t.datetime :transaction_from
    t.datetime :transaction_to
  end
end
```

それぞれのカラムは以下のような意味を持ちます。

| カラム名 | 型 | 値 |
| --- | --- | --- |
| `bitemporal_id` | `id` と同じ型 |  BTDM が共通で持つ `id` |
| `valid_from` | `datetime` | 有効時間の開始時刻 |
| `valid_to` | `datetime` | 有効時間の終了時刻 |
| `transaction_from` | `datetime` | システム時間の開始時刻 |
| `transaction_to` | `datetime` | システム時間の終了時刻 |

また、モデルクラスでは `ActiveRecord::Bitemporal` を `include` をする必要があります。

```ruby
class Employee < ActiveRecord::Base
  include ActiveRecord::Bitemporal
end
```

これで `Employee` モデルを BTDM として扱うことが出来ます。
このドキュメントではこのモデルをサンプルとしてコードを書いていきます。


## モデルインスタンスに対する操作について

ここではモデルの生成・更新・削除といったインスタンスに対する操作に関して解説します。


### 生成

以下のように BTDM を生成した場合、

```ruby
# MEMO: Timecop を使って擬似的に 2019/1/10 の日付でレコードを生成
#       データをわかりやすくする為に使用しているだけで activerecord-bitemporal には Timecop は必要ありません
employee = nil
Timecop.freeze("2019/1/10") {
  employee = Employee.create(emp_code: "001", name: "Jane")
}
```

以下のようなレコードが生成されます。

| id | bitemporal_id | emp_code | name | valid_from | valid_to | transaction_from | transaction_to |
|  --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | 001 | Jane | 2019-01-10 | 9999-12-31 | 2019-01-10 | 9999-12-31 |

この時に生成されるレコードのカラムには暗黙的に以下のような値が保存されます。

| カラム | 値 |
| --- | --- |
| `bitemporal_id` | 自身の `id` |
| `valid_from` | 生成した時間 |
| `valid_to` | 擬似的な `INFINITY` 時間 |

これは『`valid_from` から `valid_to` までの期間で有効なデータ』という意味になります。
また、 `valid_from` や `valid_to` を指定すれば『任意の時間』の履歴データも生成も出来ます。

```ruby
Timecop.freeze("2019/1/10") {
  # 現時点よりも前からのデータを生成する
  Employee.create(emp_code: "001", name: "Jane", valid_from: "2019/1/1")
}
```


### 更新

`#update` 等でモデルを更新すると『更新時間』を基準とした履歴レコードが暗黙的に生成されます。

```ruby
employee = nil
Timecop.freeze("2019/1/10") {
  employee = Employee.create(emp_code: "001", name: "Jane")
}

Timecop.freeze("2019/1/20") {
  # モデルを更新すると履歴レコードが生成される
  employee.update(name: "Tom")
  # これは #save でも同様に行われる
  # employee.name = "Tom"
  # employee.save
}
```

上記の操作を行うと以下のようなレコードが生成されます。

| id | bitemporal_id | emp_code | name | valid_from | valid_to | transaction_from | transaction_to |
|  --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | 001 | Jane | 2019-01-10 | 9999-12-31 | 2019-01-10 | 2019-01-20 |
| 2 | 1 | 001 | Jane | 2019-01-10 | 2019-01-20 | 2019-01-20 | 9999-12-31 |
| 3 | 1 | 001 | Tom | 2019-01-20 | 9999-12-31 | 2019-01-20 | 9999-12-31 |

更新時には以下のような処理を行っており、結果的に新しいレコードが2つ生成されることになります。
また、この時に生成されるレコードは共通の `bitemporal_id` を保持します。

1. 更新対象のレコード（`id = 1`）のシステム時間の終了時刻を更新する
2. 更新を行った時間までのレコード（`id = 2`）を新しく生成する
3. 更新を行った時間からのレコード（`id = 3`）を新しく生成する

activerecord-bitemporal ではレコードの内容を変更する際にレコードを直接変更するのではなくて『既存のレコードはシステム時間では参照しないような時刻』にして『変更後のレコードを新しく生成』していきます。
ただし、`#update_columns` で更新を行うと強制的にレコードが上書きされるので注意してください。

```ruby
employee = nil
Timecop.freeze("2019/1/10") {
  employee = Employee.create(emp_code: "001", name: "Jane")
}

Timecop.freeze("2019/1/20") {
  # #update_columns で更新するとレコードが直接変更される
  employee.update_columns(name: "Tom")
}
```

上記の場合は以下のようなレコードになります。
`id = 1` のレコードが直接変更されるので注意してください。

| id | bitemporal_id | emp_code | name | valid_from | valid_to | transaction_from | transaction_to |
|  --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | 001 | Tom | 2019-01-10 | 9999-12-31 | 2019-01-10 | 9999-12-31 |

履歴を生成せずに上書きして更新したいのであれば activerecord-bitemporal 側で用意している `#force_update` を利用する事が出来ます。

```ruby
employee = nil
Timecop.freeze("2019/1/10") {
  employee = Employee.create(emp_code: "001", name: "Jane")
}

Timecop.freeze("2019/1/20") {
  # #force_update のでは自身を受け取る
  # このブロック内であれば履歴を生成せずにレコードの変更が行われる
  employee.force_update { |employee|
    employee.update(name: "Tom")
  }
}
```

上記の場合は以下のレコードが生成されます。

| id | bitemporal_id | emp_code | name | valid_from | valid_to | transaction_from | transaction_to |
|  --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | 001 | Jane | 2019-01-10 | 9999-12-31 | 2019-01-10 | 2019-01-20 |
| 2 | 1 | 001 | Tom | 2019-01-10 | 9999-12-31 | 2019-01-20 | 9999-12-31 |

この場合は `id = 1` はシステムの終了時刻が更新され、新しい `id = 2` のレコードが生成されます。


### 更新時間を指定して更新

TODO:


### 削除

更新と同様にレコードのシステム時間の終了時刻を更新しつつ、新しいレコードが生成されます。

```ruby
employee = nil
Timecop.freeze("2019/1/10") {
  employee = Employee.create(emp_code: "001", name: "Jane")
}

Timecop.freeze("2019/1/20") {
  employee.update(name: "Tom")
}

Timecop.freeze("2019/1/30") {
  # 削除を行うとその時間までの履歴が生成される
  employee.destroy
}
```

上記の場合では以下のようなレコードが生成されます。

| id | bitemporal_id | emp_code | name | valid_from | valid_to | transaction_from | transaction_to |
|  --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | 001 | Jane | 2019-01-10 | 9999-12-31 | 2019-01-10 | 2019-01-20 |
| 2 | 1 | 001 | Jane | 2019-01-10 | 2019-01-20 | 2019-01-20 | 9999-12-31 |
| 3 | 1 | 001 | Tom | 2019-01-20 | 9999-12-31 | 2019-01-20 | 2019-01-30 |
| 4 | 1 | 001 | Tom | 2019-01-20 | 2019-01-30 | 2019-01-30 | 9999-12-31 |

削除も更新と同様に

1. 削除対象のレコード（`id = 3`）のシステム時間の終了時刻を更新する
2. 削除を行った時間までの履歴レコード（`id = 4`）を新しく生成する

という風に『システム時間の終了時刻を更新してから新しいレコードを生成する』という処理を行っています。


### ユニーク制約

BTDM では『履歴の時間が被っている場合』にユニーク制約のバリデーションを行います。

```ruby
Employee.create!(name: "Jane", valid_from: "2019/1/1", valid_to: "2019/1/10")

# OK : 同じ時間帯で被っていない
Employee.create!(name: "Jane", valid_from: "2019/2/1", valid_to: "2019/2/10")

# NG : 同じ時間帯で被っている
Employee.create!(name: "Jane", valid_from: "2019/2/5", valid_to: "2019/2/15")

# OK : valid_from と valid_to は同じでも問題ない
Employee.create!(name: "Jane", valid_from: "2019/2/10", valid_to: "2019/2/20")
```

また、 BTDM の `bitemporal_id` もユニーク制約となっているので注意してください。


## 検索について

BTDM のレコードの検索について解説します。


### 検索時にデフォルトで追加されるクエリ

BTDM では DB からレコードを参照する場合、暗黙的に

* 現在の時間を指定する時間指定クエリ
* 論理削除を除くクエリ

が追加された状態で SQL 文が構築されます。

```ruby
Timecop.freeze("2019/1/20") {
  # 現在の時間の履歴を返すために暗黙的に時間指定や論理削除されたレコードが除かれる
  puts Employee.all.to_sql
  # => SELECT "employees".* FROM "employees" WHERE "employees"."valid_from" <= '2019-01-20 00:00:00' AND "employees"."valid_to" > '2019-01-20 00:00:00' AND "employees"."transaction_to" = '9999-12-31 00:00:00'
}
```

これにより DB 上に複数の履歴レコードや論理削除されているレコードがあっても『現時点で有効な』レコードが参照されます。

```ruby
employee = nil
Timecop.freeze("2019/1/10") {
  employee = Employee.create(name: "Jane")
}

Timecop.freeze("2019/1/15") {
  employee.update(name: "Tom")
}

Timecop.freeze("2019/1/20") {
  # DB 上では履歴レコードや論理削除済みレコードなどが複数存在するが、暗黙的にクエリが追加されているので
  # 通常の ActiveRecord のモデルを操作した時と同じレコードを返す
  pp Employee.count
  # => 1

  pp Employee.first
  # => #<Employee:0x000055efd894e9e0
  #     id: 1,
  #     bitemporal_id: 1,
  #     emp_code: nil,
  #     name: "Tom",
  #     valid_from: 2019-01-15,
  #     valid_to: 9999-12-31,
  #     transaction_from: 2019-01-15,
  #     transaction_to: 9999-12-31>

  # 更新前の名前で検索しても引っかからない
  pp Employee.where(name: "Jane").first
  # => nil

  # なぜなら暗黙的に時間指定のクエリが追加されている為
  puts Employee.where(name: "Jane").to_sql
  # => SELECT "employees".* FROM "employees" WHERE "employees"."valid_from" <= '2019-01-20 00:00:00' AND "employees"."valid_to" > '2019-01-20 00:00:00' AND "employees"."transaction_to" = '9999-12-31 00:00:00' AND "employees"."name" = 'Jane'
}
```

このように『現在の時間で有効なレコード』のみが検索の対象となります。
また、これは `default_scope` ではなくて BTDM が独自にハックして暗黙的に追加する仕組みを実装しているので `.unscoped` で取り除く事は出来ないので注意してください。

```ruby
# default_scope であれば unscoped で無効化することが出来るが、BTDM のデフォルトクエリはそのまま
puts Employee.unscoped { Employee.all.to_sql }
# => SELECT "employees".* FROM "employees" WHERE "employees"."valid_from" <= '2019-10-25 07:56:06.731259' AND "employees"."valid_to" > '2019-10-25 07:56:06.731259' AND "employees"."transaction_to" = '9999-12-31 00:00:00'
```


### 検索時にデフォルトクエリを取り除く

検索時にデフォルトクエリを取り除きたい場合、以下のスコープを使用します。

| スコープ | 動作 |
| --- | --- |
| `.ignore_valid_datetime` | 時間指定を無視する |
| `.within_deleted` | 論理削除されているレコードを含める |
| `.without_deleted` | 論理削除されているレコードを含めない |

```ruby
Timecop.freeze("2019/1/20") {
  # 時間指定をしているクエリを取り除く
  puts Employee.ignore_valid_datetime.to_sql
  # => SELECT "employees".* FROM "employees" WHERE "employees"."transaction_to" = '9999-12-31 00:00:00'

  # 論理削除しているレコードも含める
  puts Employee.within_deleted.to_sql
  # => SELECT "employees".* FROM "employees" WHERE "employees"."valid_from" <= '2019-01-20 00:00:00' AND "employees"."valid_to" > '2019-01-20 00:00:00'

  # 全てのレコードを対象とする
  puts Employee.ignore_valid_datetime.within_deleted.to_sql
  # => SELECT "employees".* FROM "employees"
}
```

『任意のレコードの履歴一覧を取得する』ようなことを行う場合は `ignore_valid_datetime` を使用して全レコードを参照するようにします。

```ruby
employee = nil
Timecop.freeze("2019/1/10") {
  employee = Employee.create(name: "Jane")
}

Timecop.freeze("2019/1/15") {
  employee.update(name: "Tom")
}

Timecop.freeze("2019/1/20") {
  employee.update(name: "Kevin")

  # NOTE: bitemporal_id を参照することで同一の履歴を取得する事が出来る
  pp Employee.ignore_valid_datetime.where(bitemporal_id: employee.bitemporal_id).map(&:name)
  # => ["Jane", "Tom", "Kevin"]
}
```

### 時間を指定して検索する

任意の時間を指定して検索を行いたい場合、`.valid_at(datetime)` を利用する事が出来ます。

```ruby
employee1 = nil
employee2 = nil
Timecop.freeze("2019/1/10") {
  employee1 = Employee.create(emp_code: "001", name: "Jane")
}

Timecop.freeze("2019/1/15") {
  employee1.update(name: "Tom")
  employee2 = Employee.create(emp_code: "002", name: "Homu")
}

Timecop.freeze("2019/1/20") {
  # valid_at で任意の時間を参照して検索する事が出来る
  puts Employee.valid_at("2019/1/10").to_sql
  # => SELECT "employees".* FROM "employees" WHERE "employees"."valid_from" <= '2019-01-10 00:00:00' AND "employees"."valid_to" > '2019-01-10 00:00:00' AND "employees"."transaction_to" = '9999-12-31 00:00:00'

  pp Employee.valid_at("2019/1/10").map(&:name)
  # => ["Jane"]
  pp Employee.valid_at("2019/1/17").map(&:name)
  # => ["Tom", "Homu"]

  # そのまま続けてリレーション出来る
  pp Employee.valid_at("2019/1/17").where(name: "Tom").first
  # => #<Employee:0x000055678afd1d20
  #     id: 1,
  #     bitemporal_id: 1,
  #     emp_code: "001",
  #     name: "Tom",
  #     valid_from: 2019-01-15,
  #     valid_to: 9999-12-31,
  #     transaction_from: 2019-01-15,
  #     transaction_to: 9999-12-31>
}
```

また、特定の `id` で検索するのであれば `.find_at_time(datetime, id)` も利用できます。

```ruby
employee1 = nil
employee2 = nil
Timecop.freeze("2019/1/10") {
  employee1 = Employee.create(emp_code: "001", name: "Jane")
}

Timecop.freeze("2019/1/15") {
  employee1.update(name: "Tom")
  employee2 = Employee.create(emp_code: "002", name: "Homu")
}

Timecop.freeze("2019/1/20") {
  # 任意の時間の id のレコードを返す
  pp Employee.find_at_time("2019/1/12", employee1.id)
  # => #<Employee:0x000055b776d7ff18
  #     id: 1,
  #     bitemporal_id: 1,
  #     emp_code: "001",
  #     name: "Jane",
  #     valid_from: 2019-01-10,
  #     valid_to: 2019-01-15,
  #     transaction_from: 2019-01-15,
  #     transaction_to: 9999-12-31>

  # 見つからなければ nil を返す
  pp Employee.find_at_time("2019/1/12", employee2.id)
  # => nil

  # find_at_time の場合は例外を返す
  pp Employee.find_at_time!("2019/1/12", employee2.id)
  # => raise ActiveRecord::RecordNotFound (ActiveRecord::RecordNotFound)
}
```


## `id` と `bitemporal_id` について

BTDM のインスタンスの `id` は特殊で『レコードの `id`』ではなくて『`bitemporal_id` の値』が割り当てられています。

```ruby
employee = nil
Timecop.freeze("2019/1/10") {
  employee = Employee.create(emp_code: "001", name: "Jane")
}

Timecop.freeze("2019/1/15") {
  employee.update(name: "Tom")
}

Timecop.freeze("2019/1/20") {
  employee.update(name: "Kevin")

  # 現在のレコードの id は 1 を返す
  pp Employee.first.id
  # => 1

  # 別の履歴レコードを参照しても id は同じ
  pp Employee.find_at_time("2019/1/12", employee.id).id
  # => 1
}
```

インスタンスの `id` はレコードの読み込み時に自動的に設定されています。
これは `Employee.find(employee.id)` で検索を行う際に `id` の値が `レコードの id` ではなくて `bitemporal_id` のほうが実装上都合がいい、という由来になっています。
この影響により `Employee.pluck(:id)` や `Employee.map(&:id)`、 `Employee.ids` が返す結果が微妙に異なるので注意してください。

```ruby
employee = nil
Timecop.freeze("2019/1/10") {
  employee = Employee.create(emp_code: "001", name: "Jane")
}

Timecop.freeze("2019/1/15") {
  employee.update(name: "Tom")
}

Timecop.freeze("2019/1/20") {
  employee.update(name: "Kevin")

  # DB の生 id が返ってくる
  pp Employee.ignore_valid_datetime.pluck(:id)

  # bitemporal_id が返ってくる
  pp Employee.ignore_valid_datetime.map(&:id)

  # bitemporal_id が返ってくる
  pp Employee.ignore_valid_datetime.ids
}
```

レコードの内容

| id | bitemporal_id | emp_code | name | valid_from | valid_to | transaction_from | transaction_to |
|  --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | 001 | Jane | 2019-01-10 | 9999-12-31 | 2019-01-10 | 2019-01-15 |
| 2 | 1 | 001 | Jane | 2019-01-10 | 2019-01-15 | 2019-01-15 | 9999-12-31 |
| 3 | 1 | 001 | Tom | 2019-01-15 | 9999-12-31 | 2019-01-15 | 2019-01-20 |
| 4 | 1 | 001 | Tom | 2019-01-15 | 2019-01-20 | 2019-01-20 | 9999-12-31 |
| 5 | 1 | 001 | Kevin | 2019-01-20 | 9999-12-31 | 2019-01-20 | 9999-12-31 |

また、元々の DB の `id` は `#swapped_id` で参照する事が出来ます。

```ruby
employee = nil
Timecop.freeze("2019/1/10") {
  employee = Employee.create(emp_code: "001", name: "Jane")
}

Timecop.freeze("2019/1/15") {
  employee.update(name: "Tom")
}

Timecop.freeze("2019/1/20") {
  employee.update(name: "Kevin")

  pp Employee.first.swapped_id
  # => 5
  pp Employee.find_at_time("2019/1/12", employee.id).swapped_id
  # => 2
}
```

まとめると BTDM のインスタンスは以下のような値を保持しています。

* `id` : `bitemporal_id` が暗黙的に設定される
* `bitemporal_id` : BTDM 共通の `id`
* `swapped_id` : DB の生 `id`


### `id` 検索の注意点

BTDM では `find_by(id: xxx)` や `where(id: xxx)` を行う場合 `id` ではなくて `bitemporal_id` を参照する必要があります。

```ruby
# NG : BTDM の場合は id 検索出来ない
Employee.find_by(id: employee.id)

# OK : bitemporal_id で検索を行う
# MEMO: id = bitemporal_id なの
#       find_by(bitemporal_id: employee.id)
#       でも動作するが employee.bitemporal_id と書いたほうが意図が伝わりやすい
Employee.find_by(bitemporal_id: employee.bitemporal_id)

# NG : BTDM の場合は id 検索出来ない
Employee.where(id: employee.id)

# OK : bitemporal_id で検索を行う
Employee.where(bitemporal_id: employee.bitemporal_id)
```


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/kufu/activerecord-bitemporal.

## Copyright

See ./LICENSE
