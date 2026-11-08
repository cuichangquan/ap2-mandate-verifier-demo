# frozen_string_literal: true
# Invoked on either side of an actual `docker compose restart buyer seller`.
require "bundler/setup"
require "json"
require "securerandom"
require_relative "../purchase_demo/runtime"
path = File.join(PurchaseDemo::Runtime.state_dir, "restart-test.json")
authority = PurchaseDemo::Runtime.authority
case ARGV.fetch(0)
when "before"
  id = SecureRandom.uuid
  authority.approve(id: id, scenario: "timeout")
  authority.run(id: id)
  result = authority.status(id: id)
  abort "timeout was not persisted" unless result.fetch("execution_count") == 1 && result.fetch("receipt_status") == "unverified"
  File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(JSON.generate({"id" => id})) }
  puts "Before restart: one mock execution; receipt unresolved"
when "after"
  id = JSON.parse(File.binread(path)).fetch("id")
  result = authority.recover(id: id)
  abort "restart recovery failed" unless result.fetch("execution_count") == 1 && result.fetch("receipt_status") == "receipt_success"
  abort "replay executed again" unless authority.run(id: id).fetch("execution_count") == 1
  puts "After restart: original receipt verified; mock execution count remains one"
  File.unlink(path) # Remove only the completed test checkpoint, never purchase state.
else abort "unknown phase"
end
