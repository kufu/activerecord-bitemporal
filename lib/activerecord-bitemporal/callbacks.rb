# frozen_string_literal: true

module ActiveRecord::Bitemporal
  module Callbacks
    extend ActiveSupport::Concern

    included do
      define_model_callbacks :bitemporal_create
      define_model_callbacks :bitemporal_update
      define_model_callbacks :bitemporal_destroy
    end

    def destroy(...)
      perform_bitemporal_callbacks? ? run_callbacks(:bitemporal_destroy) { super } : super
    end

    def save_without_bitemporal_callbacks!(...)
      with_bitemporal_option(ignore_bitemporal_callbacks: true) {
        save!(...)
      }
    end

    private

    def _create_record
      perform_bitemporal_callbacks? ? run_callbacks(:bitemporal_create) { super } : super
    end

    def _update_record(*)
      perform_bitemporal_callbacks? ? run_callbacks(:bitemporal_update) { super } : super
    end

    def perform_bitemporal_callbacks?
      bitemporal_option[:ignore_bitemporal_callbacks] != true
    end
  end
end
