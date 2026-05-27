# frozen_string_literal: true

require_relative "lib/async/service/supervisor/envoy/version"

Gem::Specification.new do |spec|
	spec.name = "async-service-supervisor-envoy"
	spec.version = Async::Service::Supervisor::Envoy::VERSION
	
	spec.summary = "Envoy xDS monitor for async-service-supervisor."
	spec.authors = ["Samuel Williams"]
	spec.license = "MIT"
	
	spec.cert_chain  = ["release.cert"]
	spec.signing_key = File.expand_path("~/.gem/release.pem")
	
	spec.homepage = "https://github.com/socketry/async-service-supervisor-envoy"
	
	spec.metadata = {
		"documentation_uri" => "https://socketry.github.io/async-service-supervisor-envoy/",
		"source_code_uri" => "https://github.com/socketry/async-service-supervisor-envoy.git",
	}
	
	spec.files = Dir.glob(["{bake,context,lib}/**/*", "*.md"], File::FNM_DOTMATCH, base: __dir__)
	
	spec.required_ruby_version = ">= 3.3"
	
	spec.add_dependency "async", "~> 2.38"
	spec.add_dependency "async-grpc-xds"
	spec.add_dependency "async-http"
	spec.add_dependency "async-service-supervisor"
end
