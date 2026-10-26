require_relative "lib/shiplog/version"

Gem::Specification.new do |spec|
  spec.name        = "shiplog"
  spec.version     = Shiplog::VERSION
  spec.authors     = [ "Trackberry" ]
  spec.email       = [ "edouard.briere@gmail.com" ]
  spec.homepage    = "https://github.com/Trackberry/shiplog"
  spec.summary     = "Public roadmap and changelog for Rails apps, drafted from GitHub."
  spec.description = "A mountable Rails engine that turns GitHub issues, pull requests and commits into a customer-friendly roadmap and changelog, with LLM drafts approved by an admin."
  spec.license     = "MIT"

  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "README.md", "CHANGELOG.md"]
  spec.required_ruby_version = ">= 4.0"

  spec.add_dependency "rails", ">= 8.1.4", "< 9"
end
