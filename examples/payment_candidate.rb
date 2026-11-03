# frozen_string_literal: true
# Compatibility entry for the published 1.2.0 plain Ruby Payment example.
gem "ap2_mandate_verifier", "= 1.2.0"
spec = Gem::Specification.find_by_name("ap2_mandate_verifier", "1.2.0")
require File.join(spec.full_gem_path, "examples/payment.rb")
PaymentExample.run
