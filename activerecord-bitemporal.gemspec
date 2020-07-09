
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "activerecord-bitemporal/version"

Gem::Specification.new do |spec|
  spec.name          = "activerecord-bitemporal"
  spec.version       = ActiveRecord::Bitemporal::VERSION
  spec.authors       = ["mserizawa"]
  spec.email         = ["serizawa@smarthr.co.jp"]

  spec.summary       = "BiTemporal Data Model for ActiveRecord"
  spec.description   = %q{Enable ActiveRecord models to be handled as BiTemporal Data Model.}
  spec.homepage      = "https://github.com/kufu/activerecord-bitemporal"
  spec.license       = "Apache 2.0"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 5.2"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "pg"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "pry-byebug"
  spec.add_development_dependency "database_cleaner"
  spec.add_development_dependency "timecop"
end
