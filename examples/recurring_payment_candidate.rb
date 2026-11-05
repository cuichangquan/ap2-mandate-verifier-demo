# frozen_string_literal: true
# Installed candidate only; JPY ON_DEMAND, temporary synthetic ledger/mock.
gem "ap2_mandate_verifier", "= 1.6.0"
spec = Gem::Specification.find_by_name("ap2_mandate_verifier", "1.6.0")
require File.join(spec.full_gem_path, "examples/recurring_payment.rb")
RecurringPaymentExample.run
