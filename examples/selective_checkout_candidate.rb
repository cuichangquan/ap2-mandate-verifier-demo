# frozen_string_literal: true
# Candidate-only local entry; ordinary Rails and published examples remain 1.2.0.
gem "ap2_mandate_verifier", "= 1.3.0"
spec = Gem::Specification.find_by_name("ap2_mandate_verifier", "1.3.0")
require File.join(spec.full_gem_path, "examples/selective_checkout_payment.rb")
SelectiveCheckoutPaymentExample.run
