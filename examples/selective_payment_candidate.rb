# frozen_string_literal: true
# Compatibility entry for the published1.2.0 selective Payment sample.
gem "ap2_mandate_verifier", "= 1.2.0"
spec = Gem::Specification.find_by_name("ap2_mandate_verifier", "1.2.0")
require File.join(spec.full_gem_path, "examples/selective_payment.rb")
SelectivePaymentExample.run
