# frozen_string_literal: true
# Destructive to TEST TLS material only. Run in a stopped, disposable synthetic QA
# Compose project via its init container; never use against ordinary demo data.
require_relative '../purchase_demo/tls_rotate'
abort 'Set PURCHASE_TLS_FIXTURE=1 in an isolated QA project' unless ENV['PURCHASE_TLS_FIXTURE'] == '1'
mode = ARGV.fetch(0)
abort 'unsupported fixture' unless %w[expired near mismatch key_mismatch interrupt].include?(mode)
dirs = PurchaseDemo::Setup::ROLES.to_h { |role| [role, "/state-#{role}"] }
trust = '/trust'
if mode == 'interrupt'
  begin
    PurchaseDemo::TLSRotation.new(dirs: dirs, trust: trust, fault: ->(step) { raise 'test interruption' if step == 4 }).rotate!
  rescue RuntimeError => error
    raise unless error.message == 'test interruption'
    puts 'Injected rotation interruption; pending marker retained.'
    exit 0
  end
end
ca_key = OpenSSL::PKey::EC.generate('prime256v1')
ca = PurchaseDemo::Setup.certificate('fixture-ca', ca_key, nil, nil, ca: true)
if %w[expired near].include?(mode)
  ca.not_before = Time.now - 86400
  ca.not_after = Time.now + (mode == 'expired' ? -60 : 3600)
  ca.sign(ca_key, OpenSSL::Digest.new('SHA256'))
end
File.write(File.join(trust, 'ca.crt'), ca.to_pem)
%w[buyer seller].each do |role|
  key = OpenSSL::PKey::EC.generate('prime256v1')
  cert = PurchaseDemo::Setup.certificate(role, key, ca, ca_key)
  cert.not_before = ca.not_before
  cert.not_after = ca.not_after
  cert.sign(ca_key, OpenSSL::Digest.new('SHA256'))
  File.write(File.join(dirs.fetch(role), 'tls.key'), key.private_to_pem)
  File.write(File.join(dirs.fetch(role), 'tls.crt'), cert.to_pem)
  File.write(File.join(trust, "#{role}.crt"), cert.to_pem)
end
if mode == 'mismatch'
  other = OpenSSL::PKey::EC.generate('prime256v1')
  File.write(File.join(trust, 'ca.crt'), PurchaseDemo::Setup.certificate('wrong-ca', other, nil, nil, ca: true).to_pem)
elsif mode == 'key_mismatch'
  File.write(File.join(dirs.fetch('buyer'), 'tls.key'), OpenSSL::PKey::EC.generate('prime256v1').private_to_pem)
end
puts "Installed #{mode} test TLS fixture; non-TLS files untouched."
