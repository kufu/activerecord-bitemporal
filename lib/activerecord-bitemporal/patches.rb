# frozen_string_literal: true

require_relative "./bitemporal.rb"

module ActiveRecord::Bitemporal
  module Patches
    using Module.new {
      refine ::ActiveRecord::Reflection::AssociationReflection do
        # handle raise error, when `polymorphic? == true`
        def klass
          polymorphic? ? nil : super
        end
      end
    }
    using BitemporalChecker

    if ActiveRecord.version >= Gem::Version.new("8.0.0")
      module Calculations
        # Returns the base model's bitemporal IDs without patching primary_key,
        # ensuring AR::Calculations#ids compatibility with Rails 8.0+.
        # Based on <https://github.com/rails/rails/blob/v8.0.4/activerecord/lib/active_record/relation/calculations.rb#L366-L404>
        def ids
          return super unless bi_temporal_model?

          if loaded?
            result = records.map do |record|
              # Always read only bitemporal_id_key
              record._read_attribute(bitemporal_id_key)
            end
            return @async ? Promise::Complete.new(result) : result
          end

          if has_include?(bitemporal_id_key)
            relation = apply_join_dependency.group(bitemporal_id_key)
            return relation.ids
          end

          columns = arel_columns([bitemporal_id_key])
          relation = spawn
          relation.select_values = columns

          result = if relation.where_clause.contradiction?
            ActiveRecord::Result.empty
          else
            skip_query_cache_if_necessary do
              model.with_connection do |c|
                c.select_all(relation, "#{model.name} Ids", async: @async)
              end
            end
          end

          result.then { |result| type_cast_pluck_values(result, columns) }
        end
      end
    end

    # nested_attributes 用の拡張
    module Persistence
      using Module.new {
        refine Persistence do
          def copy_bitemporal_option(src, dst)
            return unless [src.class, dst.class].all? { |klass|
              # NOTE: Can't call refine method.
              # klass.bi_temporal_model?
              klass.include?(ActiveRecord::Bitemporal)
            }
            dst.bitemporal_option_merge! src.bitemporal_option
          end
        end
      }

      # MEMO: このメソッドは BTDM 以外にもフックする必要がある
      def assign_nested_attributes_for_one_to_one_association(association_name, _attributes)
        super
        target = send(association_name)
        return if target.nil? || !target.changed?
        copy_bitemporal_option(self, target)
      end

      def assign_nested_attributes_for_collection_association(association_name, _attributes_collection)
        # Preloading records
        send(association_name).load if association(association_name).klass&.bi_temporal_model?
        super
        send(association_name)&.each do |target|
          next unless target.changed?
          copy_bitemporal_option(self, target)
        end
      end
    end

    module Association
      def skip_statement_cache?(scope)
        super || bi_temporal_model?
      end

      def scope
        scope = super
        return scope unless scope.bi_temporal_model?

        scope_ = scope
        if owner.class&.bi_temporal_model?
          if owner.valid_datetime
            valid_datetime = owner.valid_datetime
            scope_ = scope_.valid_at(valid_datetime)
            scope_.merge!(scope_.bitemporal_value[:through].valid_at(valid_datetime)) if scope_.bitemporal_value[:through]
          end

          if owner.transaction_datetime
            transaction_datetime = owner.transaction_datetime
            scope_ = scope_.transaction_at(transaction_datetime)
            scope_.merge!(scope_.bitemporal_value[:through].transaction_at(transaction_datetime)) if scope_.bitemporal_value[:through]
          end
        end
        return scope_
      end

      private

      def bi_temporal_model?
        owner.class.bi_temporal_model? && klass&.bi_temporal_model?
      end

      def matches_foreign_key?(record)
        return super unless owner.class.bi_temporal_model?

        begin
          original_owner_id = owner.id
          owner.id = owner.read_attribute(owner.class.bitemporal_id_key)
          super
        ensure
          owner.id = original_owner_id
        end
      end
    end

    module ThroughAssociation
      def target_scope
        scope = super
        return scope unless scope.bi_temporal_model?

        reflection.chain.drop(1).each do |reflection|
          klass = reflection.klass&.scope_for_association&.klass
          next unless klass&.bi_temporal_model?
          scope.bitemporal_value[:through] = klass
        end
        scope
      end
    end

    module AssociationReflection
      JoinKeys = Struct.new(:key, :foreign_key)
      def get_join_keys(association_klass)
        return super unless association_klass&.bi_temporal_model?
        self.belongs_to? ? JoinKeys.new(association_klass.bitemporal_id_key, join_foreign_key) : super
      end

      def primary_key(klass)
        return super unless klass&.bi_temporal_model?
        klass.bitemporal_id_key
      end
    end

    module Merger
      def merge
        if relation.klass.bi_temporal_model? && other.klass.bi_temporal_model?
          relation.bitemporal_value.merge! other.bitemporal_value
        end
        super
      end
    end

    module SingularAssociation
      # MEMO: Except for primary_key in ActiveRecord
      #       https://github.com/rails/rails/blob/6-0-stable/activerecord/lib/active_record/associations/singular_association.rb#L34-L36
      #       excluding bitemporal_id_key
      def scope_for_create
        return super unless klass&.bi_temporal_model?
        super.except!(klass.bitemporal_id_key)
      end
    end
  end
end
