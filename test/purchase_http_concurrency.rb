# frozen_string_literal: true
# Run in buyer after authority has approved an unused valid purchase. Only the
# last synthetic approval is selected; no keys or signed bytes are printed.
require "bundler/setup"
require_relative "../purchase_demo/runtime"
row = PurchaseDemo::Store.new.read(ARGV.fetch(0))
row = nil unless row && row.fetch("scenario") == "valid" && !row["wires"]
abort "approve a fresh valid concurrency fixture first" unless row
id = row.fetch("id")
client = PurchaseDemo::Transport.new(role: "buyer")
offer = client.a2a(command: "offer", payload: {"purchase_id" => id})
wires = PurchaseDemo::Protocol.close(approval: row.fetch("approval"), checkout_jwt: offer.fetch("checkout_jwt"),
  agent_key: PurchaseDemo::Runtime.private_key, public_keys: PurchaseDemo::Runtime.public_keys,
  nonce: offer.fetch("nonce"), now: Time.now.to_i)
PurchaseDemo::Store.new.update(id) { |record| record.merge("wires" => wires) }
ready, start = Queue.new, Queue.new
workers = 4.times.map do
  Thread.new do
    transport = PurchaseDemo::Transport.new(role: "buyer")
    ready << true
    start.pop
    transport.a2a(command: "purchase", payload: {"purchase_id" => id, "wires" => wires})
  end
end
4.times { ready.pop }
4.times { start << true }
workers.each(&:value)
result = client.a2a(command: "status", payload: {"purchase_id" => id})
abort "concurrent purchase did not settle once" unless result.fetch("acceptance_state") == "receipt_success" && result.fetch("summary").fetch("execution_count") == 1
checked = PurchaseDemo::Protocol.verify_receipt(receipt_jwt: result.fetch("receipt_jwt"), closed_sd_jwt: wires.fetch("payment_closed"),
  context: PurchaseDemo::Protocol.receipt_context(payment_id: id, merchant_public_key_pem: PurchaseDemo::Runtime.public_keys.fetch(:merchant),
    not_before: row.fetch("approval").fetch("issued_at"), not_after: row.fetch("approval").fetch("issued_at") + 86_400), now: Time.now.to_i)
abort "concurrent receipt invalid" unless checked.verified? && checked.payment_succeeded?
puts "Four concurrent real A2A requests: one durable mock execution; original Receipt verified"
