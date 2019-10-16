module ActiveRecord
  module Bitemporal
    module BitemporalChecker
      refine ::Class do
        def bi_temporal_model?
          include?(ActiveRecord::Bitemporal)
        end
      end

      refine ::ActiveRecord::Relation do
        def bi_temporal_model?
          klass.include?(ActiveRecord::Bitemporal)
        end
      end
    end
    using BitemporalChecker

    module Optionable
      def bitemporal_option
        ::ActiveRecord::Bitemporal.merge_by(bitemporal_option_storage)
      end

      def bitemporal_option_merge!(other)
        self.bitemporal_option_storage = bitemporal_option.merge other
      end

      def with_bitemporal_option(**opt)
        tmp_opt = bitemporal_option_storage
        self.bitemporal_option_storage = tmp_opt.merge(opt)
        yield self
      ensure
        self.bitemporal_option_storage = tmp_opt
      end

    private
      def bitemporal_option_storage
        @bitemporal_option_storage ||= {}
      end

      def bitemporal_option_storage=(value)
        @bitemporal_option_storage = value
      end
    end

    # Add Optionable to Bitemporal
    # Example:
    # ActiveRecord::Bitemporal.valid_at("2018/4/1") {
    #   # in valid_datetime is "2018/4/1".
    # }
    module ::ActiveRecord::Bitemporal
      class Current < ActiveSupport::CurrentAttributes
        attribute :option
      end

      class << self
        include Optionable

        def valid_at(datetime, &block)
          with_bitemporal_option(ignore_valid_datetime: false, valid_datetime: datetime, &block)
        end

        def valid_at!(datetime, &block)
          with_bitemporal_option(ignore_valid_datetime: false, valid_datetime: datetime, force_valid_datetime: true, &block)
        end

        def valid_datetime
          bitemporal_option[:valid_datetime]&.in_time_zone&.to_datetime
        end

        def ignore_valid_datetime(&block)
          with_bitemporal_option(ignore_valid_datetime: true, valid_datetime: nil, &block)
        end

        def merge_by(option)
          if bitemporal_option_storage[:force_valid_datetime]
            bitemporal_option_storage.merge(option.merge(valid_datetime: bitemporal_option_storage[:valid_datetime]))
          else
            bitemporal_option_storage.merge(option)
          end
        end

      private
        def bitemporal_option_storage
          Current.option ||= {}
        end

        def bitemporal_option_storage=(value)
          Current.option = value
        end
      end
    end

    # Relation 拡張用
    module Relation
      class BitemporalClause
        attr_reader :predicates

        def initialize(predicates = {})
          @predicates = predicates
        end

        def [](klass)
          @predicates[klass] ||= {}
        end

        def []=(klass, value)
          @predicates[klass] = value
        end

        def ast(klass: nil, table: nil)
          return predicates.keys.map { |klass| ast(klass: klass, table: table) }.select(&:present?).inject(&:and) unless klass

          option = ::ActiveRecord::Bitemporal.merge_by(self[klass] || {})

          table = klass.arel_table unless table
          table = option[:through].arel_table if option[:through].present?
          arels = []
          if !option[:ignore_valid_datetime]
            target_datetime = option[:valid_datetime]&.in_time_zone&.to_datetime || Time.current
            arels << table[:valid_from].lteq(target_datetime).and(table[:valid_to].gt(target_datetime))
          end
          arels << table[:deleted_at].eq(nil) unless option[:within_deleted]
          arels.inject(&:and)
        end
      end

      module Finder
        def with_bitemporal_option(**opt)
          all.tap { |relation| relation.bitemporal_option_merge!(**opt) }
        end

        def find(*ids)
          return super if block_given?
          expects_array = ids.first.kind_of?(Array) || ids.size > 1
          ids = ids.first if ids.first.kind_of?(Array)
          where(bitemporal_id_key => ids).yield_self { |it| expects_array ? it&.to_a : it&.take }.presence || raise(::ActiveRecord::RecordNotFound)
        end

        def find_at_time!(datetime, *ids)
          valid_at(datetime).find(*ids)
        end

        def find_at_time(datetime, *ids)
          find_at_time!(datetime, *ids)
        rescue ActiveRecord::RecordNotFound
          expects_array = ids.first.kind_of?(Array) || ids.size > 1
          expects_array ? [] : nil
        end
      end
      include Optionable
      include Finder

      def valid_datetime
        bitemporal_option[:valid_datetime]&.in_time_zone&.to_datetime
      end

      def load
        return super if loaded?
        # このタイミングで先読みしているアソシエーションが読み込まれるので時間を固定
        records = ActiveRecord::Bitemporal.with_bitemporal_option(bitemporal_option) { super }

        return records if records.empty? || bitemporal_option[:ignore_valid_datetime]
        records.each do |record|
          record.bitemporal_option_merge! bitemporal_option.except(:ignore_valid_datetime)
        end
      end

      def build_arel(args = nil)
        ActiveRecord::Bitemporal.with_bitemporal_option(bitemporal_option) {
          super.tap { |arel|
            bitemporal_clause.ast(table: table)&.tap { |clause|
              arel.ast.cores.each do |node|
                next unless node.kind_of?(Arel::Nodes::SelectCore)
                if node.wheres.empty?
                  node.wheres = [clause]
                else
                  node.wheres[0] = clause.and(node.wheres[0])
                end
              end
            }
          }
        }
      end

      def bitemporal_clause
        @values[:bitemporal_clause].yield_self { |result|
          next result if result
          self.bitemporal_clause = Relation::BitemporalClause.new
        }
      end

      def bitemporal_clause=(value)
        @values[:bitemporal_clause] = value
      end

      def primary_key
        bitemporal_id_key
      end

      private

      def bitemporal_option_storage(klass_ = self.klass)
        bitemporal_clause[klass_]
      end

      def bitemporal_option_storage=(value)
        bitemporal_clause[klass] = value
      end
    end

    # リレーションのスコープ
    module Scope
      extend ActiveSupport::Concern

      included do
        scope :valid_at, -> (datetime) {
          with_bitemporal_option(ignore_valid_datetime: false, valid_datetime: datetime)
        }
        scope :ignore_valid_datetime, -> {
          with_bitemporal_option(ignore_valid_datetime: true, valid_datetime: nil)
        }
        scope :within_deleted, -> {
          with_bitemporal_option(within_deleted: true)
        }
        scope :without_deleted, -> {
          with_bitemporal_option(within_deleted: false)
        }
        scope :bitemporal_for, -> (id) {
          where(bitemporal_id: id)
        }
        scope :valid_in, -> (from: nil, to: nil) {
          table_name = klass.table_name
          column_valid_to = "#{table_name}.valid_to"
          column_valid_from = "#{table_name}.valid_from"
          ignore_valid_datetime
            .tap { |relation| break relation.where("? <= #{column_valid_to}", from.in_time_zone.to_datetime) if from }
            .tap { |relation| break relation.where("#{column_valid_from} <= ?", to.in_time_zone.to_datetime) if to }
        }
        scope :valid_allin, -> (from: nil, to: nil) {
          table_name = klass.table_name
          column_valid_to = "#{table_name}.valid_to"
          column_valid_from = "#{table_name}.valid_from"
          ignore_valid_datetime
            .tap { |relation| break relation.where("? <= #{column_valid_from}", from.in_time_zone.to_datetime) if from }
            .tap { |relation| break relation.where("#{column_valid_to} <= ?", to.in_time_zone.to_datetime) if to }
        }
      end

      module Extension
        extend ActiveSupport::Concern

        included do
          scope :bitemporal_histories, -> (*ids) {
            ignore_valid_datetime.bitemporal_for(*ids)
          }
          def self.bitemporal_most_future(id)
            bitemporal_histories(id).order(valid_from: :asc).last
          end
          def self.bitemporal_most_past(id)
            bitemporal_histories(id).order(valid_from: :asc).first
          end
        end
      end

      module Experimental
        extend ActiveSupport::Concern
      end
    end

    # create, update, destroy に処理をフックする
    module Persistence
      module PersistenceOptionable
        include Optionable

        def force_update(&block)
          with_bitemporal_option(fource_update: true, &block)
        end

        def force_update?
          bitemporal_option[:fource_update].present?
        end

        def valid_at(datetime, &block)
          with_bitemporal_option(valid_datetime: datetime, &block)
        end

        def valid_datetime
          bitemporal_option[:valid_datetime]&.in_time_zone&.to_datetime
        end
      end
      include PersistenceOptionable

      using Module.new {
        refine Persistence do
          def build_new_instance
            self.class.new.tap { |it|
              (self.class.column_names - %w(id type created_at updated_at) - bitemporal_ignore_update_columns.map(&:to_s)).each { |name|
                # 生のattributesの値でなく、ラッパーメソッド等を考慮してpublic_send(name)する
                it.public_send("#{name}=", public_send(name))
              }
            }
          end
        end

        refine Object do
          # MEMO: Do not copy `swapped_id`
          def dup(*)
            super.tap { |itself|
              itself.instance_exec { @_swapped_id = nil } unless itself.frozen?
            }
          end
        end
      }

      module EachAssociation
        refine ActiveRecord::Persistence do
          def each_association(
            deep: false,
            ignore_associations: [],
            only_cached: false,
            &block
          )
            klass = self.class
            enum = Enumerator.new { |y|
              reflections = klass.reflect_on_all_associations
              reflections.each { |reflection|
                next if only_cached && !association_cached?(reflection.name)

                associations = reflection.collection? ? public_send(reflection.name) : [public_send(reflection.name)]
                associations.compact.each { |asso|
                  next if ignore_associations.include? asso
                  ignore_associations << asso
                  y << asso
                  asso.each_association(deep: deep, ignore_associations: ignore_associations, only_cached: only_cached) { |it| y << it } if deep
                }
              }
              self
            }
            enum.each(&block)
          end
        end
      end
      using EachAssociation

      def _create_record(attribute_names = self.attribute_names)
        # 自身の `valid_from` を設定
        self.valid_from = valid_datetime || Time.current if self.valid_from == ActiveRecord::Bitemporal::DEFAULT_VALID_FROM

        # アソシエーションの子に対して `valid_from` を設定
        # MEMO: cache が存在しない場合、 public_send(reflection.name) のタイミングで新しくアソシエーションオブジェクトが生成されるが
        # この時に何故か生成できずに落ちるケースがあるので cache しているアソシエーションに対してのみイテレーションする
        each_association(deep: true, only_cached: true)
          .select { |asso| asso.class.bi_temporal_model? && asso.valid_from == ActiveRecord::Bitemporal::DEFAULT_VALID_FROM && asso.new_record? }
          .each   { |asso| asso.valid_from = self.valid_from }
        super()
      end

      def save(*)
        ActiveRecord::Base.transaction(requires_new: true) do
          self.class.where(bitemporal_id: self.id).lock!.pluck(:id)
          super
        end
      end

      def save!(*)
        ActiveRecord::Base.transaction(requires_new: true) do
          self.class.where(bitemporal_id: self.id).lock!.pluck(:id)
          super
        end
      end

      def _update_row(attribute_names, attempted_action = 'update')
        current_time = Time.current
        target_datetime = valid_datetime || current_time
        # NOTE: force_update の場合は自身のレコードを取得するような時間を指定しておく
        target_datetime = valid_from if force_update?

        # MEMO: このメソッドに来るまでに validation が発動しているので、以後 validate は考慮しなくて大丈夫
        ActiveRecord::Base.transaction(requires_new: true) do
          # 対象基準日において有効なレコード
          # NOTE: 論理削除対象
          current_valid_record = self.class.find_at_time(target_datetime, self.id)&.tap { |record|
            # 元々の id を詰めておく
            record.id = record.swapped_id
            record.clear_changes_information
          }

          # 履歴データとして保存する新しいインスタンス
          # NOTE: 以前の履歴データ(現時点で有効なレコードを元にする)
          before_instance = current_valid_record.dup
          # NOTE: 以降の履歴データ(自身のインスタンスを元にする)
          after_instance = build_new_instance

          # force_update の場合は既存のレコードを論理削除した上で新しいレコードを生成する
          if current_valid_record.present? && force_update?
            # 有効なレコードは論理削除する
            current_valid_record.update_columns(deleted_at: current_time)
            # 以降の履歴データはそのまま保存
            after_instance.created_at = current_time
            after_instance.save!(validate: false)

          # 有効なレコードがある場合
          elsif current_valid_record.present?
            # 有効なレコードは論理削除する
            current_valid_record.update_columns(deleted_at: current_time)

            # 以前の履歴データは valid_to を詰めて保存
            before_instance.valid_to = target_datetime
            raise ActiveRecord::Rollback if before_instance.valid_from_cannot_be_greater_equal_than_valid_to
            before_instance.created_at = current_time
            before_instance.save!(validate: false)

            # 以降の履歴データは valid_from と valid_to を調整して保存する
            after_instance.valid_from = target_datetime
            after_instance.valid_to = current_valid_record.valid_to
            raise ActiveRecord::Rollback if after_instance.valid_from_cannot_be_greater_equal_than_valid_to
            after_instance.created_at = current_time
            after_instance.save!(validate: false)

          # 有効なレコードがない場合
          else
            # 一番近い未来にある Instance を取ってきて、その valid_from を valid_to に入れる
            nearest_instance = self.class.where(bitemporal_id: bitemporal_id).where('valid_from > ?', target_datetime).ignore_valid_datetime.order(valid_from: :asc).first

            # valid_from と valid_to を調整して保存する
            after_instance.valid_from = target_datetime
            after_instance.valid_to = nearest_instance.valid_from
            after_instance.save!(validate: false)
          end
          # update 後に新しく生成したインスタンスのデータを移行する
          @_swapped_id = after_instance.swapped_id
          self.valid_from = after_instance.valid_from

          return 1
        # MEMO: Must return false instead of nil, if `#_update_row` failure.
        end || false
      end

      def destroy(force_delete: false)
        return super() if force_delete

        current_time = Time.current
        target_datetime = valid_datetime || current_time

        with_transaction_returning_status do
          duplicated_instance = self.class.find_at_time(target_datetime, self.id).dup

          @destroyed = false
          _run_destroy_callbacks {
            @destroyed = update_columns(deleted_at: current_time)

            # 削除時の状態を履歴レコードとして保存する
            duplicated_instance.valid_to = target_datetime
            duplicated_instance.created_at = current_time
            duplicated_instance.save!(validate: false)
          }
          raise ActiveRecord::Rollback unless @destroyed

          self
        rescue
          @destroyed = false
          false
        end
      end

      module ::ActiveRecord::Persistence
        # MEMO: Must be override ActiveRecord::Persistence#reload
        alias_method :active_record_bitemporal_original_reload, :reload
        def reload(options = nil)
          return active_record_bitemporal_original_reload(options) unless self.class.bi_temporal_model?

          self.class.connection.clear_query_cache

          fresh_object =
            if options && options[:lock]
              self.class.unscoped { self.class.lock(options[:lock]).find(id) }
            else
              self.class.unscoped { self.class.find(id) }
            end

          @attributes = fresh_object.instance_variable_get("@attributes")
          @new_record = false
          # NOTE: Hook to copying swapped_id
          @_swapped_id = fresh_object.swapped_id
          self
        end
      end
    end

    module Uniqueness
      private
      def scope_relation(record, relation)
        finder_class = find_finder_class_for(record)
        return super unless finder_class.bi_temporal_model?

        relation = super(record, relation)

        target_datetime = record.valid_datetime || Time.current

        valid_from = record.valid_from.yield_self { |valid_from|
          # NOTE: valid_from が初期値の場合は現在の時間を基準としてバリデーションする
          # valid_from が初期値の場合は Persistence#_create_record に Time.current が割り当てられる為
          # バリデーション時と生成時で若干時間がずれてしまうことには考慮する
          if valid_from == ActiveRecord::Bitemporal::DEFAULT_VALID_FROM
            target_datetime
          # NOTE: 新規作成時以外では target_datetime の値を基準としてバリデーションする
          # 更新時にバリデーションする場合、valid_from の時間ではなくて target_datetime の時間を基準としているため
          # valdi_from を基準としてしまうと整合性が取れなくなってしまう
          elsif !record.new_record?
            target_datetime
          else
            valid_from
          end
        }

        # MEMO: `force_update` does not refer to` valid_datetime`
        valid_from = record.valid_from if record.force_update?

        valid_to = record.valid_to.yield_self { |valid_to|
          # レコードを更新する時に valid_datetime が valid_from ~ valid_to の範囲外だった場合、
          #   一番近い未来の履歴レコードを参照して更新する
          # という仕様があるため、それを考慮して valid_to を設定する
          if (record.valid_datetime && (record.valid_from..record.valid_to).include?(record.valid_datetime)) == false && (record.persisted?)
            finder_class.where(bitemporal_id: record.bitemporal_id).where('? < valid_from', target_datetime).ignore_valid_datetime.order(valid_from: :asc).first.valid_from
          else
            valid_to
          end
        }

        bitemporal_scope = finder_class.unscoped.ignore_valid_datetime
            .where("valid_from < ?", valid_to).where("? < valid_to", valid_from)
            .yield_self { |scope|
              # MEMO: #dup などでコピーした場合、id は存在しないが swapped_id のみ存在するケースがあるので
              # id と swapped_id の両方が存在する場合のみクエリを追加する
              record.id && record.swapped_id ? scope.where.not(id: record.swapped_id) : scope
            }
        relation.merge(bitemporal_scope)
      end
    end
  end
end
