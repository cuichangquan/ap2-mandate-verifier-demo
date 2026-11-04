# frozen_string_literal: true
# Published example. Synthetic only; no candidate archive or source overlay.
gem "ap2_mandate_verifier", "= 1.3.0"
spec = Gem::Specification.find_by_name("ap2_mandate_verifier", "1.3.0")
require File.join(spec.full_gem_path, "examples/selective_payment.rb")
SelectivePaymentExample.run
