# frozen_string_literal: true

module ActiveRecord::Bitemporal
  class BitemporalError < StandardError; end

  class ValidDatetimeRangeError < BitemporalError; end
end
