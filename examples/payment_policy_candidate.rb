# frozen_string_literal: true
# Candidate-only installed SDK example. Normal Rails/public routes remain1.3.0.
gem "ap2_mandate_verifier", "= 1.4.0"
spec = Gem::Specification.find_by_name("ap2_mandate_verifier", "1.4.0")
require File.join(spec.full_gem_path, "examples/payment_policy.rb")
PaymentPolicyExample.run
