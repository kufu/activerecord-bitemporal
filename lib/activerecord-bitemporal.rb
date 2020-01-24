require "active_record"
require "active_support/core_ext/time/calculations"
require "activerecord-bitemporal/bitemporal"
require "activerecord-bitemporal/patches"
require "activerecord-bitemporal/version"

module ActiveRecord::Bitemporal
  DEFAULT_VALID_FROM = Time.utc(1900, 12, 31).in_time_zone.freeze
  DEFAULT_VALID_TO   = Time.utc(9999, 12, 31).in_time_zone.freeze

  extend ActiveSupport::Concern
  included do
    bitemporalize
  end
end

module ActiveRecord::Bitemporal::Bitemporalize
  using Module.new {
    refine ::ActiveRecord::Base do
      class << ::ActiveRecord::Base
        def prepend_relation_delegate_class(mod)
          relation_delegate_class(ActiveRecord::Relation).prepend mod
          relation_delegate_class(ActiveRecord::AssociationRelation).prepend mod
          relation_delegate_class(ActiveRecord::Associations::CollectionProxy).prepend mod
        end
      end
    end
  }

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

    def inherited(klass)
      super
      klass.prepend_relation_delegate_class ActiveRecord::Bitemporal::Relation
    end
  end

  module InstanceMethods
    include ActiveRecord::Bitemporal::Persistence

    def swap_id!(without_clear_changes_information: false)
      @_swapped_id = self.id
      self.id = self.send(bitemporal_id_key)
      clear_changes_information unless without_clear_changes_information
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

    def created_at_cannot_be_greater_equal_than_deleted_at
      if created_at && deleted_at && created_at >= deleted_at
        errors.add(:created_at, "can't be greater equal than deleted_at")
      end
    end
  end

  def bitemporalize(enable_strict_by_validates_bitemporal_id: false)
    extend ClassMethods
    include InstanceMethods
    include ActiveRecord::Bitemporal::Scope

    after_create do
      # MEMO: #update_columns is not call #_update_row (and validations, callbacks)
      update_columns(bitemporal_id_key => swapped_id) unless send(bitemporal_id_key)
      swap_id!(without_clear_changes_information: true)
    end

    after_find do
      self.swap_id! if self.send(bitemporal_id_key).present?
    end

    attribute :valid_from, :datetime, default: -> { ActiveRecord::Bitemporal::DEFAULT_VALID_FROM }
    attribute :valid_to, :datetime, default: -> { ActiveRecord::Bitemporal::DEFAULT_VALID_TO }

    # Callback hook to `validates :xxx, uniqueness: true`
    const_set(:UniquenessValidator, Class.new(ActiveRecord::Validations::UniquenessValidator) {
      prepend ActiveRecord::Bitemporal::Uniqueness
    })

    # validations
    validates :valid_from, presence: true
    validates :valid_to, presence: true
    validate :valid_from_cannot_be_greater_equal_than_valid_to
    validate :created_at_cannot_be_greater_equal_than_deleted_at

    validates bitemporal_id_key, uniqueness: true, allow_nil: true, strict: enable_strict_by_validates_bitemporal_id

    prepend_relation_delegate_class ActiveRecord::Bitemporal::Relation
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::Base
    .extend ActiveRecord::Bitemporal::Bitemporalize

  ActiveRecord::Base
    .prepend ActiveRecord::Bitemporal::Patches::Persistence

  ActiveRecord::Relation::Merger
    .prepend ActiveRecord::Bitemporal::Patches::Merger

  ActiveRecord::Associations::Association
    .prepend ActiveRecord::Bitemporal::Patches::Association

  ActiveRecord::Associations::ThroughAssociation
    .prepend ActiveRecord::Bitemporal::Patches::ThroughAssociation

  ActiveRecord::Associations::SingularAssociation
    .prepend ActiveRecord::Bitemporal::Patches::SingularAssociation

  ActiveRecord::Reflection::AssociationReflection
    .prepend ActiveRecord::Bitemporal::Patches::AssociationReflection
end
