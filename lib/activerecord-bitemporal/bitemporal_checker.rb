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
  end
end
