# frozen_string_literal: true

require "active_record"
require "active_support/core_ext/time/calculations"
require "activerecord-bitemporal/scope"
require "activerecord-bitemporal/errors"
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

ActiveSupport.on_load(:active_record) do
  require "activerecord-bitemporal/bitemporal"
  require "activerecord-bitemporal/bitemporalize"
  require "activerecord-bitemporal/patches"

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
