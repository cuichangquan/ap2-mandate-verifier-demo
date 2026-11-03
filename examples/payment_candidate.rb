# frozen_string_literal: true
# Opt-in unpublished candidate only; default Rails demo stays on published 1.0.0.
gem "ap2_mandate_verifier", "= 1.1.0"
spec = Gem::Specification.find_by_name("ap2_mandate_verifier", "1.1.0")
require File.join(spec.full_gem_path, "examples/payment.rb")
PaymentExample.run
