# frozen_string_literal: true
# Published Gem only; keys and checkout data are synthetic and process-local.
gem "ap2_mandate_verifier", "= 1.5.0"
spec = Gem::Specification.find_by_name("ap2_mandate_verifier", "1.5.0")
require File.join(spec.full_gem_path, "examples/selective_checkout_payment.rb")
SelectiveCheckoutPaymentExample.run
