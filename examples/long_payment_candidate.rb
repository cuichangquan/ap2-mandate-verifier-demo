# frozen_string_literal: true
# Installed long-profile candidate, optional pinned SQLite; synthetic only.
gem "ap2_mandate_verifier", "= 1.6.0"
spec = Gem::Specification.find_by_name("ap2_mandate_verifier", "1.6.0")
require File.join(spec.full_gem_path, "examples/long_payment_acceptance.rb")
LongPaymentAcceptanceExample.run
