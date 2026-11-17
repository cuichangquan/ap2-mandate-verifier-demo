# frozen_string_literal: true
require "ap2_mandate_verifier"
spec = Gem.loaded_specs.fetch("ap2_mandate_verifier")
abort "candidate version mismatch" unless spec.version.to_s == ENV.fetch("EXPECTED_CANDIDATE_VERSION")
abort "source checkout loaded instead of installed Gem" unless $LOADED_FEATURES.grep(/ap2_mandate_verifier\.rb$/).all? { |path| path.start_with?(spec.full_gem_path + "/") }
abort "diagnostic API missing" unless AP2MandateVerifier::Diagnostic.respond_to?(:payment_flow)
abort "start outcome API missing" unless AP2MandateVerifier::PaymentAcceptance::Service.instance_methods.include?(:start_with_diagnostic)
puts "Installed candidate #{spec.version}: public diagnostic APIs present"
