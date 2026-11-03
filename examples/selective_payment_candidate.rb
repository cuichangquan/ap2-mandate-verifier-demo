# frozen_string_literal: true
# Explicit unpublished candidate; ordinary Rails startup remains on public1.1.0.
gem "ap2_mandate_verifier", "= 1.2.0"
spec = Gem::Specification.find_by_name("ap2_mandate_verifier", "1.2.0")
require File.join(spec.full_gem_path, "examples/selective_payment.rb")
SelectivePaymentExample.run
