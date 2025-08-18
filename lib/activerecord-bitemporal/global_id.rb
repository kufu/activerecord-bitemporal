# frozen_string_literal: true

begin
  require "globalid"
rescue LoadError
  # If GlobalID is not available, we skip the GlobalID integration.
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

      class BitemporalLocator < ::GlobalID::Locator::BaseLocator
        private

        # @override https://github.com/rails/globalid/blob/v1.2.1/lib/global_id/locator.rb#L203
        def primary_key(model_class)
          model_class.respond_to?(:bitemporal_id_key) ? model_class.bitemporal_id_key : :id
        end
      end
    end
  end
end

# BiTemporal Data Model requires default scope, so `UnscopedLocator` cannot be used.
GlobalID::Locator.use :bitemporal, ActiveRecord::Bitemporal::GlobalID::BitemporalLocator.new
