# frozen_string_literal: true

require_relative "lib/activerecord-bitemporal/version"

Gem::Specification.new do |spec|
  spec.name          = "activerecord-bitemporal"
  spec.version       = ActiveRecord::Bitemporal::VERSION
  spec.authors       = ["SmartHR"]
  spec.email         = ["oss@smarthr.co.jp"]

  spec.summary       = "BiTemporal Data Model for ActiveRecord"
  spec.description   = %q{Enable ActiveRecord models to be handled as BiTemporal Data Model.}
  spec.homepage      = "https://github.com/kufu/activerecord-bitemporal"
  spec.license       = "Apache 2.0"
  spec.required_ruby_version = ">= 3.1"

  spec.files         = Dir["lib/**/*", "CHANGELOG.md", "LICENSE", "README.md"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  rails_requirements = ">= 7.1"
  spec.add_dependency "activerecord", rails_requirements
  spec.add_dependency "activesupport", rails_requirements
end
