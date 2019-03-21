require "active_record"
require "active_support/core_ext/time/calculations"
require "activerecord-bitemporal/bitemporal"
require "activerecord-bitemporal/patches"
require "activerecord-bitemporal/version"

module ActiveRecord
  module Bitemporal
    DEFAULT_VALID_FROM = Time.utc(1900, 12, 31).in_time_zone.freeze
    DEFAULT_VALID_TO   = Time.utc(9999, 12, 31).in_time_zone.freeze

    include ActiveRecord::Bitemporal::Persistence
    extend ActiveSupport::Concern

    module ClassMethods
      include ActiveRecord::Bitemporal::Relation::Finder

      def bitemporal_id_key
        'bitemporal_id'
      end

      # Override ActiveRecord::Core::ClassMethods#cached_find_by_statement
      # `.find_by` not use caching
      def cached_find_by_statement(key, &block)
        ActiveRecord::StatementCache.create(connection, &block)
      end
    end

    def swap_id!
      @_swapped_id = self.id
      self.id = self.send(bitemporal_id_key)
      clear_changes_information
    end

    def swapped_id
      @_swapped_id || self.id
    end

    def bitemporal_id_key
      self.class.bitemporal_id_key
    end

    def bitemporal_ignore_update_columns
      []
    end

    def id_in_database
      swapped_id.presence || super
    end

    def valid_from_cannot_be_greater_equal_than_valid_to
      if valid_from && valid_to && valid_from >= valid_to
        errors.add(:valid_from, "can't be greater equal than valid_to")
      end
    end

    # Callback hook to `validates :xxx, uniqueness: true`
    const_set(:UniquenessValidator, Class.new(ActiveRecord::Validations::UniquenessValidator) {
      prepend ActiveRecord::Bitemporal::Uniqueness
    })

    included do
      after_create do
        # MEMO: #update_columns is not call #_update_row (and validations, callbacks)
        update_columns(bitemporal_id_key => swapped_id) unless send(bitemporal_id_key)
      end

      after_find do
        self.swap_id! if self.send(bitemporal_id_key).present?
      end

      attribute :valid_from, :datetime, default: -> { DEFAULT_VALID_FROM }
      attribute :valid_to, :datetime, default: -> { DEFAULT_VALID_TO }

      # validations
      validates :valid_from, presence: true
      validates :valid_to, presence: true
      validate :valid_from_cannot_be_greater_equal_than_valid_to

      validates! bitemporal_id_key, uniqueness: true, allow_nil: true

      # リレーションメソッドの追加
      const_get(:ActiveRecord_Relation).prepend ActiveRecord::Bitemporal::Relation
      const_get(:ActiveRecord_AssociationRelation).prepend ActiveRecord::Bitemporal::Relation
      const_get(:ActiveRecord_Associations_CollectionProxy).prepend ActiveRecord::Bitemporal::Relation
      # 継承先の Relation にも追加する
      def self.inherited(subclass)
        super
        subclass.const_get(:ActiveRecord_Relation).prepend ActiveRecord::Bitemporal::Relation
        subclass.const_get(:ActiveRecord_AssociationRelation).prepend ActiveRecord::Bitemporal::Relation
        subclass.const_get(:ActiveRecord_Associations_CollectionProxy).prepend ActiveRecord::Bitemporal::Relation
      end

      include ActiveRecord::Bitemporal::Scope
    end
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::Base
    .prepend ActiveRecord::Bitemporal::Patches::Persistence

  ActiveRecord::Relation::Merger
    .prepend ActiveRecord::Bitemporal::Patches::Merger

  ActiveRecord::Associations::Association
    .prepend ActiveRecord::Bitemporal::Patches::Association

  ActiveRecord::Associations::ThroughAssociation
    .prepend ActiveRecord::Bitemporal::Patches::ThroughAssociation

  ActiveRecord::Reflection::AssociationReflection
    .prepend ActiveRecord::Bitemporal::Patches::AssociationReflection
end
