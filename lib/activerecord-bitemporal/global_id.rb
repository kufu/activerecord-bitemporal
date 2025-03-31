# frozen_string_literal: true

begin
  require "globalid"
rescue LoadError
  return
end

module ActiveRecord
  module Bitemporal
    module GlobalID
      include ::GlobalID::Identification

      def to_global_id(options = {})
        super(options.merge(app: "bitemporal"))
      end
      alias to_gid to_global_id
    end
  end
end

# BiTemporal Data Model requires default scope, so `UnscopedLocator` cannot be used.
GlobalID::Locator.use "bitemporal", GlobalID::Locator::BaseLocator.new
