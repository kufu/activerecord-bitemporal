# frozen_string_literal: true

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

        def valid_datetime
          bitemporal_option[:valid_datetime]&.in_time_zone&.to_datetime
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

    module Relation
      module Finder
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
      include Finder

      def load
        return super if loaded?

        # このタイミングで先読みしているアソシエーションが読み込まれるので時間を固定
        records = ActiveRecord::Bitemporal.valid_at(valid_datetime) { super }

        return records if records.empty?
        return records unless bitemporal_value[:with_valid_datetime] && valid_datetime

        records.each do |record|
          record.send(:bitemporal_option_storage)[:valid_datetime] = valid_datetime
        end
      end

      def primary_key
        bitemporal_id_key
      end
    end

    # create, update, destroy に処理をフックする
    module Persistence
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

      module PersistenceOptionable
        include Optionable

        def force_update(&block)
          with_bitemporal_option(force_update: true, &block)
        end

        def force_update?
          bitemporal_option[:force_update].present?
        end

        def valid_at(datetime, &block)
          with_bitemporal_option(valid_datetime: datetime, &block)
        end

        def bitemporal_option_merge_with_association!(other)
          bitemporal_option_merge!(other)

          # Only cached associations will be walked for performance issues
          each_association(deep: true, only_cached: true).each do |association|
            next unless association.respond_to?(:bitemporal_option_merge!)
            association.bitemporal_option_merge!(other)
          end
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

          def has_column?(name)
            self.class.column_names.include? name.to_s
          end

          def assign_transaction_to(value)
            if has_column?(:deleted_at)
              assign_attributes(transaction_to: value, deleted_at: value)
            else
              assign_attributes(transaction_to: value)
            end
          end

          def update_transaction_to(value)
            if has_column?(:deleted_at)
              update_columns(transaction_to: value, deleted_at: value)
            else
              update_columns(transaction_to: value)
            end
          end
        end

        refine ActiveRecord::Base do
          # MEMO: Do not copy `swapped_id`
          def dup(*)
            super.tap { |itself|
              itself.instance_exec { @_swapped_id = nil } unless itself.frozen?
            }
          end
        end
      }

      def _create_record(attribute_names = self.attribute_names)
        bitemporal_assign_initialize_value(valid_datetime: self.valid_datetime)

        ActiveRecord::Bitemporal.valid_at!(self.valid_from) {
          super()
        }
      end

      def save(**)
        ActiveRecord::Base.transaction(requires_new: true) do
          self.class.where(bitemporal_id: self.id).lock!.pluck(:id) if self.id
          super
        end
      end

      def save!(**)
        ActiveRecord::Base.transaction(requires_new: true) do
          self.class.where(bitemporal_id: self.id).lock!.pluck(:id) if self.id
          super
        end
      end

      def _update_row(attribute_names, attempted_action = 'update')
        current_valid_record, before_instance, after_instance = bitemporal_build_update_records(valid_datetime: self.valid_datetime, force_update: self.force_update?)

        # MEMO: このメソッドに来るまでに validation が発動しているので、以後 validate は考慮しなくて大丈夫
        ActiveRecord::Base.transaction(requires_new: true) do
          current_valid_record&.update_transaction_to(current_valid_record.transaction_to)
          before_instance&.save!(validate: false)
          # NOTE: after_instance always exists
          after_instance.save!(validate: false)

          # update 後に新しく生成したインスタンスのデータを移行する
          @_swapped_id = after_instance.swapped_id
          self.valid_from = after_instance.valid_from

          1
        # MEMO: Must return false instead of nil, if `#_update_row` failure.
        end || false
      end

      def destroy(force_delete: false)
        return super() if force_delete

        current_time = Time.current
        target_datetime = valid_datetime || current_time

        duplicated_instance = self.class.find_at_time(target_datetime, self.id).dup

        ActiveRecord::Base.transaction(requires_new: true, joinable: false) do
          @destroyed = false
          _run_destroy_callbacks {
            @destroyed = update_transaction_to(current_time)

            # 削除時の状態を履歴レコードとして保存する
            duplicated_instance.valid_to = target_datetime
            duplicated_instance.transaction_from = current_time
            duplicated_instance.save!(validate: false)
          }
          raise ActiveRecord::RecordInvalid unless @destroyed

          self
        end
      rescue => e
        @destroyed = false
        @_association_destroy_exception = ActiveRecord::RecordNotDestroyed.new("Failed to destroy the record: class=#{e.class}, message=#{e.message}", self)
        false
      end

      module ::ActiveRecord::Persistence
        # MEMO: Must be override ActiveRecord::Persistence#reload
        alias_method :active_record_bitemporal_original_reload, :reload unless method_defined? :active_record_bitemporal_original_reload
        if Gem::Version.new("7.0.0.alpha") <= ActiveRecord.version
          def reload(options = nil)
            return active_record_bitemporal_original_reload(options) unless self.class.bi_temporal_model?

            self.class.connection.clear_query_cache

            fresh_object = if apply_scoping?(options)
              _find_record(options)
            else
              self.class.unscoped { self.class.bitemporal_default_scope.scoping { _find_record(options) } }
            end

            @association_cache = fresh_object.instance_variable_get(:@association_cache)
            @attributes = fresh_object.instance_variable_get(:@attributes)
            @new_record = false
            @previously_new_record = false
            # NOTE: Hook to copying swapped_id
            @_swapped_id = fresh_object.swapped_id
            bitemporal_option_storage[:relation_valid_datetime] = fresh_object.relation_valid_datetime
            self
          end
        elsif Gem::Version.new("6.1.0") <= ActiveRecord.version
          def reload(options = nil)
            return active_record_bitemporal_original_reload(options) unless self.class.bi_temporal_model?

            self.class.connection.clear_query_cache

            fresh_object =
              if options && options[:lock]
                self.class.unscoped { self.class.lock(options[:lock]).bitemporal_default_scope.find(id) }
              else
                self.class.unscoped { self.class.bitemporal_default_scope.find(id) }
              end

            @attributes = fresh_object.instance_variable_get(:@attributes)
            @new_record = false
            @previously_new_record = false
            # NOTE: Hook to copying swapped_id
            @_swapped_id = fresh_object.swapped_id
            bitemporal_option_storage[:valid_datetime] = fresh_object.valid_datetime
            self
          end
        else
          def reload(options = nil)
            return active_record_bitemporal_original_reload(options) unless self.class.bi_temporal_model?

            self.class.connection.clear_query_cache

            fresh_object =
              if options && options[:lock]
                self.class.unscoped { self.class.lock(options[:lock]).bitemporal_default_scope.find(id) }
              else
                self.class.unscoped { self.class.bitemporal_default_scope.find(id) }
              end

            @attributes = fresh_object.instance_variable_get("@attributes")
            @new_record = false
            # NOTE: Hook to copying swapped_id
            @_swapped_id = fresh_object.swapped_id
            bitemporal_option_storage[:valid_datetime] = fresh_object.valid_datetime
            self
          end
        end
      end

      private

      def bitemporal_assign_initialize_value(valid_datetime:, current_time: Time.current)
        # 自身の `valid_from` を設定
        self.valid_from = valid_datetime || current_time if self.valid_from == ActiveRecord::Bitemporal::DEFAULT_VALID_FROM

        self.transaction_from = current_time if self.transaction_from == ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_FROM

         # Assign only if defined created_at and deleted_at
        if has_column?(:created_at)
          self.transaction_from = self.created_at if changes.key?("created_at")
          self.created_at = self.transaction_from
        end
        if has_column?(:deleted_at)
          self.transaction_to = self.deleted_at if changes.key?("deleted_at")
          self.deleted_at = self.transaction_to == ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO ? nil : self.transaction_to
        end
      end

      def bitemporal_build_update_records(valid_datetime:, current_time: Time.current, force_update: false)
        target_datetime = valid_datetime || current_time
        # NOTE: force_update の場合は自身のレコードを取得するような時間を指定しておく
        target_datetime = valid_from_changed? ? valid_from_was : valid_from if force_update

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
        if current_valid_record.present? && force_update
          # 有効なレコードは論理削除する
          current_valid_record.assign_transaction_to(current_time)
          # 以前の履歴データは valid_from/to を更新しないため、破棄する
          before_instance = nil
          # 以降の履歴データはそのまま保存
          after_instance.transaction_from = current_time

        # 有効なレコードがある場合
        elsif current_valid_record.present?
          # 有効なレコードは論理削除する
          current_valid_record.assign_transaction_to(current_time)

          # 以前の履歴データは valid_to を詰めて保存
          before_instance.valid_to = target_datetime
          raise ActiveRecord::RecordInvalid.new(before_instance) if before_instance.valid_from_cannot_be_greater_equal_than_valid_to
          before_instance.transaction_from = current_time

          # 以降の履歴データは valid_from と valid_to を調整して保存する
          after_instance.valid_from = target_datetime
          after_instance.valid_to = current_valid_record.valid_to
          raise ActiveRecord::RecordInvalid.new(after_instance) if after_instance.valid_from_cannot_be_greater_equal_than_valid_to
          after_instance.transaction_from = current_time

        # 有効なレコードがない場合
        else
          # 一番近い未来にある Instance を取ってきて、その valid_from を valid_to に入れる
          nearest_instance = self.class.where(bitemporal_id: bitemporal_id).bitemporal_where_bind("valid_from", :gt, target_datetime).ignore_valid_datetime.order(valid_from: :asc).first
          if nearest_instance.nil?
            message = "Update failed: Couldn't find #{self.class} with 'bitemporal_id'=#{self.bitemporal_id} and 'valid_from' < #{target_datetime}"
            raise ActiveRecord::RecordNotFound.new(message, self.class, "bitemporal_id", self.bitemporal_id)
          end

          # 有効なレコードは存在しない
          current_valid_record = nil

          # 以前の履歴データは有効なレコードを基準に生成するため、存在しない
          before_instance = nil

          # 以降の履歴データは valid_from と valid_to を調整して保存する
          after_instance.valid_from = target_datetime
          after_instance.valid_to = nearest_instance.valid_from
          after_instance.transaction_from = current_time
        end

        [current_valid_record, before_instance, after_instance]
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

        # MEMO: `force_update` does not refer to `valid_datetime`
        valid_from = record.valid_from if record.force_update?

        valid_to = record.valid_to.yield_self { |valid_to|
          # レコードを更新する時に valid_datetime が valid_from ~ valid_to の範囲外だった場合、
          #   一番近い未来の履歴レコードを参照して更新する
          # という仕様があるため、それを考慮して valid_to を設定する
          if (record.valid_datetime && (record.valid_from..record.valid_to).cover?(record.valid_datetime)) == false && (record.persisted?)
            finder_class.where(bitemporal_id: record.bitemporal_id).bitemporal_where_bind("valid_from", :gt, target_datetime).ignore_valid_datetime.order(valid_from: :asc).first.valid_from
          else
            valid_to
          end
        }

        valid_at_scope = finder_class.unscoped.ignore_valid_datetime
            .bitemporal_where_bind("valid_from", :lt, valid_to).bitemporal_where_bind("valid_to", :gt, valid_from)
            .yield_self { |scope|
              # MEMO: #dup などでコピーした場合、id は存在しないが swapped_id のみ存在するケースがあるので
              # id と swapped_id の両方が存在する場合のみクエリを追加する
              record.id && record.swapped_id ? scope.where.not(id: record.swapped_id) : scope
            }

        # MEMO: Must refer Time.current, when not new record
        #       Because you don't want transaction_from to be rewritten
        transaction_from = record.new_record? ? (record.transaction_from || Time.current) : Time.current
        transaction_to = record.transaction_to || ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO
        transaction_at_scope = finder_class.unscoped
          .ignore_valid_datetime
          .within_deleted
          .bitemporal_where_bind("transaction_to", :gt, transaction_from)
          .bitemporal_where_bind("transaction_from", :lt, transaction_to)

        puts relation.merge(valid_at_scope).merge(transaction_at_scope).to_sql if $debug
        relation.merge(valid_at_scope).merge(transaction_at_scope)
      end
    end
  end
end
