# frozen_string_literal: true
# Synthetic temporary SQLite DB/mock processor; not a production ledger.
gem "ap2_mandate_verifier", "= 1.5.0"
spec = Gem::Specification.find_by_name("ap2_mandate_verifier", "1.5.0")
require File.join(spec.full_gem_path, "examples/payment_acceptance.rb")
PaymentAcceptanceExample.run
