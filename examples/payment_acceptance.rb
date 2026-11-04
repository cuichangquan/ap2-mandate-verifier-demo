# frozen_string_literal: true
# Published SDK only; temporary synthetic ledger/mock, no production payment.
gem "ap2_mandate_verifier", "= 1.5.0"
spec = Gem::Specification.find_by_name("ap2_mandate_verifier", "1.5.0")
require File.join(spec.full_gem_path, "examples/payment_acceptance.rb")
PaymentAcceptanceExample.run
