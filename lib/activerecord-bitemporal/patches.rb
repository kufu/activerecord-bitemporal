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

        if owner.class&.bi_temporal_model? && (owner.valid_datetime || owner.bitemporal_option[:relation_valid_datetime])
          valid_datetime = owner.valid_datetime || owner.bitemporal_option[:relation_valid_datetime]
          scope.merge!(klass.valid_at(valid_datetime))
          scope.merge!(scope.bitemporal_value[:through].valid_at(valid_datetime)) if scope.bitemporal_value[:through]
        end
        return scope
      end

      private

      def bi_temporal_model?
        owner.class.bi_temporal_model? && klass&.bi_temporal_model?
      end
    end

    module ThroughAssociation
      def target_scope
        scope = super
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

      def association_scope_cache(conn, owner, &block)
        clear_association_scope_cache if klass&.bi_temporal_model?
        super
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
