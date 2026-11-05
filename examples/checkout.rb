# frozen_string_literal: true
# Published Gem only. Synthetic approval/keys; no application execution.
gem "ap2_mandate_verifier", "= 1.6.0"
spec = Gem::Specification.find_by_name("ap2_mandate_verifier", "1.6.0")
require File.join(spec.full_gem_path, "examples/conditional_checkout.rb")
ConditionalCheckoutExample.run
