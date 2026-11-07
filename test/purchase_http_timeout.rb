# frozen_string_literal: true
# Runs in buyer. A fresh timeout approval must exist. This proves the actual
# client timeout path, not merely a server-side 'unknown' label.
require "bundler/setup"
require_relative "../purchase_demo/runtime"
store = PurchaseDemo::Store.new
row = store.read(ARGV.fetch(0))
row = nil unless row && row.fetch("scenario") == "timeout" && !row["wires"]
abort "fresh timeout approval required" unless row
id = row.fetch("id")
client = PurchaseDemo::Transport.new(role: "buyer")
offer = client.a2a(command: "offer", payload: {"purchase_id" => id})
wires = PurchaseDemo::Protocol.close(approval: row.fetch("approval"), checkout_jwt: offer.fetch("checkout_jwt"),
  agent_key: PurchaseDemo::Runtime.private_key, public_keys: PurchaseDemo::Runtime.public_keys,
  nonce: offer.fetch("nonce"), now: Time.now.to_i)
store.update(id) { |record| record.merge("wires" => wires) }
timed_out = false
begin
  client.a2a(command: "purchase", payload: {"purchase_id" => id, "wires" => wires})
rescue PurchaseDemo::Transport::Error => error
  timed_out = error.code == :timeout
end
abort "real transport timeout was not observed" unless timed_out
status = client.a2a(command: "status", payload: {"purchase_id" => id})
abort "timeout did not follow exactly one persisted effect" unless status.fetch("acceptance_state") == "unknown" && status.fetch("summary").fetch("execution_count") == 1
recovered = PurchaseDemo::Runtime.buyer.control({"command" => "recover", "purchase_id" => id})
abort "timeout recovery did not verify original receipt" unless recovered.fetch("summary").fetch("receipt_status").include?("真正なSuccess") && recovered.fetch("summary").fetch("execution_count") == 1
puts "Actual TLS HTTP read timeout observed after one persisted effect; original Receipt recovered without reexecution"
