# frozen_string_literal: true

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
      if self[valid_from_key] && self[valid_to_key] && self[valid_from_key] >= self[valid_to_key]
        errors.add(valid_from_key, "can't be greater equal than #{valid_to_key}")
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
    enable_merge_with_except_bitemporal_default_scope: false,
    valid_from_key: :valid_from,
    valid_to_key: :valid_to
  )
    return if ancestors.include? InstanceMethods

    extend ClassMethods
    include InstanceMethods
    include ActiveRecord::Bitemporal
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

    self.class_attribute :valid_from_key, :valid_to_key, instance_writer: false
    self.valid_from_key = valid_from_key.to_s
    self.valid_to_key = valid_to_key.to_s
    attribute valid_from_key, default: ActiveRecord::Bitemporal::DEFAULT_VALID_FROM
    attribute valid_to_key, default: ActiveRecord::Bitemporal::DEFAULT_VALID_TO
    attribute :transaction_from, default: ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_FROM
    attribute :transaction_to, default: ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO

    # Callback hook to `validates :xxx, uniqueness: true`
    const_set(:UniquenessValidator, Class.new(ActiveRecord::Validations::UniquenessValidator) {
      prepend ActiveRecord::Bitemporal::Uniqueness
    })

    # validations
    validates valid_from_key, presence: true
    validates valid_to_key, presence: true
    validates :transaction_from, presence: true
    validates :transaction_to, presence: true
    validate :valid_from_cannot_be_greater_equal_than_valid_to
    validate :transaction_from_cannot_be_greater_equal_than_transaction_to

    validates bitemporal_id_key, uniqueness: true, allow_nil: true, strict: enable_strict_by_validates_bitemporal_id

    prepend_relation_delegate_class ActiveRecord::Bitemporal::Relation
    relation_delegate_class(ActiveRecord::Associations::CollectionProxy).prepend ActiveRecord::Bitemporal::CollectionProxy
  end
end
