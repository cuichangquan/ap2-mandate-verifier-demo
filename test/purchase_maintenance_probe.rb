# frozen_string_literal: true
# Only use with a dedicated synthetic verification project.
require 'json'
require 'digest'
require 'sqlite3'
require_relative '../purchase_demo/runtime'
require_relative '../purchase_demo/setup'
mode = ARGV.fetch(0)
if mode == 'seed'
  authority = PurchaseDemo::Runtime.authority
  ids = %w[valid timeout].to_h do |scenario|
    id = SecureRandom.uuid
    authority.approve(id: id, scenario: scenario)
    authority.run(id: id)
    [scenario, id]
  end
  File.write(File.join(PurchaseDemo::Runtime.state_dir, '.maintenance-ids.json'), JSON.generate(ids))
  puts 'Seeded completed and response-unknown synthetic purchases.'
elsif %w[snapshot compare].include?(mode)
  dirs = PurchaseDemo::Setup::ROLES.to_h { |role| [role, "/state-#{role}"] }
  snapshot = {}
  PurchaseDemo::Setup.required_files(dirs: dirs, trust: '/trust').each do |path, _|
    next if %w[tls.key tls.crt ca.crt buyer.crt seller.crt].include?(File.basename(path))
    if path.end_with?('.sqlite3')
      db = SQLite3::Database.new(path, flags: SQLite3::Constants::Open::READONLY)
      begin
        tables = db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").flatten
        content = tables.to_h do |table|
          quoted = '"' + table.gsub('"', '""') + '"'
          [table, db.execute("SELECT * FROM #{quoted}").sort_by { |row| JSON.generate(row) }]
        end
        snapshot[path] = Digest::SHA256.hexdigest(JSON.generate(content))
      ensure
        db.close
      end
    else
      snapshot[path] = Digest::SHA256.file(path).hexdigest
    end
  end
  path = '/state-authority/.maintenance-snapshot.json'
  if mode == 'snapshot'
    File.write(path, JSON.generate(snapshot))
  else
    abort 'Non-TLS persistent data changed during maintenance' unless JSON.parse(File.read(path)) == snapshot
  end
  puts "#{mode}: #{snapshot.size} non-TLS artifacts verified (contents not logged)."
elsif mode == 'recover'
  ids = JSON.parse(File.read(File.join(PurchaseDemo::Runtime.state_dir, '.maintenance-ids.json')))
  ids.each_value do |id|
    summary = PurchaseDemo::Runtime.authority.recover(id: id)
    abort 'Payment execution count changed' unless summary.fetch('execution_count') == 1
    abort 'Original purchase ID changed' unless summary.fetch('purchase_id') == id
    abort 'Saved receipt not recovered' unless summary.fetch('receipt_status') == 'receipt_success'
  end
  puts 'Original IDs and saved receipts recovered; each processor execution count remains one.'
else
  abort 'Unknown test mode'
end
