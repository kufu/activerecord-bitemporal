# frozen_string_literal: true

require "active_record"
require "active_support/core_ext/time/calculations"
require "activerecord-bitemporal/bitemporal"
require "activerecord-bitemporal/scope"
require "activerecord-bitemporal/errors"
require "activerecord-bitemporal/patches"
require "activerecord-bitemporal/version"
require "activerecord-bitemporal/visualizer"
require "activerecord-bitemporal/callbacks"

module ActiveRecord::Bitemporal
  DEFAULT_VALID_FROM = Time.utc(1900, 12, 31).in_time_zone.freeze
  DEFAULT_VALID_TO   = Time.utc(9999, 12, 31).in_time_zone.freeze
  DEFAULT_TRANSACTION_FROM = Time.utc(1900, 12, 31).in_time_zone.freeze
  DEFAULT_TRANSACTION_TO   = Time.utc(9999, 12, 31).in_time_zone.freeze

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
        end
      end
    end
  }

  module ClassMethods
    include ActiveRecord::Bitemporal::Relation::Finder

    DEFAULT_ATTRIBUTES = {
      valid_from:       ActiveRecord::Bitemporal::DEFAULT_VALID_FROM,
      valid_to:         ActiveRecord::Bitemporal::DEFAULT_VALID_TO,
      transaction_from: ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_FROM,
      transaction_to:   ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO
    }.freeze

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
      klass.relation_delegate_class(ActiveRecord::Associations::CollectionProxy).prepend ActiveRecord::Bitemporal::CollectionProxy
      if relation_delegate_class(ActiveRecord::Relation).ancestors.include? ActiveRecord::Bitemporal::Relation::MergeWithExceptBitemporalDefaultScope
        klass.relation_delegate_class(ActiveRecord::Relation).prepend ActiveRecord::Bitemporal::Relation::MergeWithExceptBitemporalDefaultScope
      end
    end

  private
    def load_schema!
      super

      DEFAULT_ATTRIBUTES.each do |name, default_value|
        type = type_for_attribute(name)
        define_attribute(name.to_s, type, default: default_value)
      end
    end
  end

  module InstanceMethods
    include ActiveRecord::Bitemporal::Persistence

    def swap_id!(without_clear_changes_information: false)
      @_swapped_id_previously_was = nil
      @_swapped_id = self.id
      self.id = self.send(bitemporal_id_key)
      clear_attribute_changes([:id]) unless without_clear_changes_information
    end

    def swapped_id
      @_swapped_id || self.id
    end

    def swapped_id_previously_was
      @_swapped_id_previously_was
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

    def previously_force_updated?
      @previously_force_updated
    end

    def valid_from_cannot_be_greater_equal_than_valid_to
      if valid_from && valid_to && valid_from >= valid_to
        errors.add(:valid_from, "can't be greater equal than valid_to")
      end
    end

    def transaction_from_cannot_be_greater_equal_than_transaction_to
      if transaction_from && transaction_to && transaction_from >= transaction_to
        errors.add(:transaction_from, "can't be greater equal than transaction_to")
      end
    end
  end

  def bitemporalize(
    enable_strict_by_validates_bitemporal_id: false,
    enable_default_scope: true,
    enable_merge_with_except_bitemporal_default_scope: false
  )
    extend ClassMethods
    include InstanceMethods
    include ActiveRecord::Bitemporal::Scope
    include ActiveRecord::Bitemporal::Callbacks

    if enable_merge_with_except_bitemporal_default_scope
      relation_delegate_class(ActiveRecord::Relation).prepend ActiveRecord::Bitemporal::Relation::MergeWithExceptBitemporalDefaultScope
    end

    if enable_default_scope
      default_scope {
        bitemporal_default_scope
      }
    end

    after_create do
      # MEMO: #update_columns is not call #_update_row (and validations, callbacks)
      update_columns(bitemporal_id_key => swapped_id) unless send(bitemporal_id_key)
      swap_id!(without_clear_changes_information: true)
      @previously_force_updated = false
    end

    after_find do
      self.swap_id! if self.send(bitemporal_id_key).present?
      @previously_force_updated = false
    end

    # Callback hook to `validates :xxx, uniqueness: true`
    const_set(:UniquenessValidator, Class.new(ActiveRecord::Validations::UniquenessValidator) {
      prepend ActiveRecord::Bitemporal::Uniqueness
    })

    # validations
    validates :valid_from, presence: true
    validates :valid_to, presence: true
    validates :transaction_from, presence: true
    validates :transaction_to, presence: true
    validate :valid_from_cannot_be_greater_equal_than_valid_to
    validate :transaction_from_cannot_be_greater_equal_than_transaction_to

    validates bitemporal_id_key, uniqueness: true, allow_nil: true, strict: enable_strict_by_validates_bitemporal_id

    prepend_relation_delegate_class ActiveRecord::Bitemporal::Relation
    relation_delegate_class(ActiveRecord::Associations::CollectionProxy).prepend ActiveRecord::Bitemporal::CollectionProxy
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
