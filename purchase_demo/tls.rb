# frozen_string_literal: true
require 'openssl'
require 'time'

module PurchaseDemo
  # Diagnostics contain public certificate metadata and fixed reason codes only.
  module TLS
    WARNING_SECONDS = 48 * 60 * 60
    PENDING = '.tls-rotation.json'
    module_function

    def status(role:, state_dir:, trust_dir:, now: Time.now)
      reasons = []
      certificates = {}
      reasons << 'rotation_pending' if File.exist?(File.join(trust_dir, PENDING))
      ca = read_certificate(File.join(trust_dir, 'ca.crt'))
      certificates['ca'] = metadata(ca, now)
      reasons.concat(time_reasons(ca, now))
      reasons << 'ca_mismatch' unless ca.verify(ca.public_key) && ca.extensions.any? { |e| e.oid == 'basicConstraints' && e.value.include?('CA:TRUE') }
      if role == 'authority'
        %w[buyer seller].each do |peer|
          path = File.join(trust_dir, "#{peer}.crt")
          next unless File.file?(path)
          peer_cert = read_certificate(path)
          certificates[peer] = metadata(peer_cert, now)
          reasons.concat(time_reasons(peer_cert, now))
          reasons << 'ca_mismatch' unless peer_cert.issuer == ca.subject && peer_cert.verify(ca.public_key)
        end
      end
      if %w[buyer seller].include?(role)
        cert = read_certificate(File.join(state_dir, 'tls.crt'))
        certificates[role] = metadata(cert, now)
        reasons.concat(time_reasons(cert, now))
        key = OpenSSL::PKey.read(File.binread(File.join(state_dir, 'tls.key')))
        reasons << 'key_mismatch' unless cert.check_private_key(key)
        reasons << 'ca_mismatch' unless cert.issuer == ca.subject && cert.verify(ca.public_key)
        reasons << 'hostname_mismatch' unless OpenSSL::SSL.verify_certificate_identity(cert, role)
        store = OpenSSL::X509::Store.new
        store.add_cert(ca)
        store.time = now
        store.purpose = OpenSSL::X509::PURPOSE_SSL_SERVER
        reasons << 'invalid_chain' unless store.verify(cert)
      end
      reasons.uniq!
      blocking = reasons - ['expiring']
      {'status' => blocking.empty? ? 'ready' : 'certificate_update_required',
       'certificates' => certificates, 'reasons' => reasons,
       'update_required' => !reasons.empty?}
    rescue Errno::ENOENT
      {'status' => 'preparing', 'certificates' => certificates, 'reasons' => ['missing_tls_files'], 'update_required' => false}
    rescue StandardError
      {'status' => 'certificate_update_required', 'certificates' => certificates, 'reasons' => ['invalid_tls_material'], 'update_required' => true}
    end

    def read_certificate(path)
      raise 'unsafe certificate' if File.symlink?(path)
      OpenSSL::X509::Certificate.new(File.binread(path))
    end

    def metadata(cert, now)
      {'source' => 'persisted', 'not_before' => cert.not_before.utc.iso8601, 'not_after' => cert.not_after.utc.iso8601,
       'remaining_seconds' => (cert.not_after - now).floor,
       'update_required' => cert.not_after <= now + WARNING_SECONDS || cert.not_before > now}
    end

    def time_reasons(cert, now)
      return ['not_yet_valid'] if cert.not_before > now
      return ['expired'] if cert.not_after <= now
      cert.not_after <= now + WARNING_SECONDS ? ['expiring'] : []
    end
  end
end
