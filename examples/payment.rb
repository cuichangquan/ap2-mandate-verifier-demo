# frozen_string_literal: true
# Published SDK sample; synthetic data only, no live processor or Rails required.
gem "ap2_mandate_verifier", "= 1.3.0"
spec = Gem::Specification.find_by_name("ap2_mandate_verifier", "1.3.0")
require File.join(spec.full_gem_path, "examples/payment.rb")
PaymentExample.run
