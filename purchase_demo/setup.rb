# frozen_string_literal: true
require 'openssl'
require 'securerandom'
require 'fileutils'
require_relative 'store'

module PurchaseDemo
  module Setup
    ROLES = %w[authority buyer seller].freeze
    module_function

    def write(path, data, mode: 0o600)
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, mode) { |f| f.write(data) }
      File.chown(10001, 10001, path) if Process.uid.zero?
    end

    def required_files(dirs:, trust:)
      private_names = {
        'authority' => %w[signing_key.pem state.sqlite3 session_secret buyer_control.token seller_control.token],
        'buyer' => %w[signing_key.pem state.sqlite3 tls.key tls.crt buyer_control.token seller_a2a.token],
        'seller' => %w[signing_key.pem state.sqlite3 acceptance.sqlite3 tls.key tls.crt seller_control.token seller_a2a.token]
      }
      private_files = private_names.flat_map do |role, names|
        names.map { |name| [File.join(dirs.fetch(role), name), true] }
      end
      private_files + %w[ca.crt authority.pub.pem buyer.pub.pem seller.pub.pem].map { |name| [File.join(trust, name), false] }
    end

    def validate_existing!(dirs:, trust:)
      required_files(dirs: dirs, trust: trust).each do |path, private_file|
        unless File.file?(path) && !File.symlink?(path) && File.size(path).positive? &&
            (!private_file || (File.stat(path).mode & 0o077).zero?)
          raise 'incomplete or unsafe existing setup; do not regenerate automatically'
        end
      end
      true
    end

    def run!
      File.umask(0o077)
      dirs = ROLES.to_h { |role| [role, "/state-#{role}"] }
      trust = '/trust'
      if File.exist?(File.join(trust, '.initialized'))
        validate_existing!(dirs: dirs, trust: trust)
        copy_public_tls!(dirs: dirs, trust: trust) unless File.exist?(File.join(trust, '.tls-rotation.json'))
        return
      end
      # Never replace keys/ledgers after a partial or previous initialization.
      raise 'partial setup requires explicit removal of demo volumes' if dirs.values.any? { |dir| Dir.exist?(dir) && !Dir.children(dir).empty? } || (Dir.exist?(trust) && !Dir.children(trust).empty?)
      (dirs.values + [trust]).each do |dir|
        FileUtils.mkdir_p(dir, mode: 0o700)
        File.chown(10001, 10001, dir) if Process.uid.zero?
      end
      File.chmod(0o755, trust)
      ca_key = OpenSSL::PKey::EC.generate('prime256v1')
      ca = certificate('purchase-demo-ca', ca_key, nil, nil, ca: true)
      write(File.join(trust, 'ca.crt'), ca.to_pem, mode: 0o644)
      ROLES.each do |role|
        key = OpenSSL::PKey::EC.generate('prime256v1')
        write(File.join(dirs.fetch(role), 'signing_key.pem'), key.private_to_pem)
        write(File.join(trust, "#{role}.pub.pem"), key.public_to_pem, mode: 0o644)
        next if role == 'authority'
        tls_key = OpenSSL::PKey::EC.generate('prime256v1')
        cert = certificate(role, tls_key, ca, ca_key)
        write(File.join(dirs.fetch(role), 'tls.key'), tls_key.private_to_pem)
        write(File.join(dirs.fetch(role), 'tls.crt'), cert.to_pem)
        write(File.join(trust, "#{role}.crt"), cert.to_pem, mode: 0o644)
      end
      { 'seller_a2a' => %w[buyer seller], 'seller_control' => %w[authority seller], 'buyer_control' => %w[authority buyer] }.each do |name, recipients|
        token = SecureRandom.hex(32)
        recipients.each { |role| write(File.join(dirs.fetch(role), "#{name}.token"), token) }
      end
      write(File.join(dirs.fetch('authority'), 'session_secret'), SecureRandom.hex(64))
      ROLES.each do |role|
        Store.bootstrap(role: role, state_dir: dirs.fetch(role))
        if Process.uid.zero?
          Dir.glob(File.join(dirs.fetch(role), '*')).each { |file| File.chown(10001, 10001, file) }
        end
      end
      write(File.join(trust, '.initialized'), '1', mode: 0o644)
    end

    # Add only public copies for older volumes; never replace any credentials.
    def copy_public_tls!(dirs:, trust:)
      %w[buyer seller].each do |role|
        path = File.join(trust, "#{role}.crt")
        next if File.exist?(path)
        cert = OpenSSL::X509::Certificate.new(File.binread(File.join(dirs.fetch(role), 'tls.crt')))
        write(path, cert.to_pem, mode: 0o644)
      end
    end

    def certificate(name, key, issuer, issuer_key, ca: false)
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = SecureRandom.random_number(2**128)
      cert.subject = OpenSSL::X509::Name.parse("/CN=#{name}")
      cert.issuer = issuer ? issuer.subject : cert.subject
      cert.public_key = key
      cert.not_before = Time.now - 60
      cert.not_after = Time.now + 7 * 24 * 60 * 60
      factory = OpenSSL::X509::ExtensionFactory.new
      factory.subject_certificate = cert
      factory.issuer_certificate = issuer || cert
      cert.add_extension(factory.create_extension('basicConstraints', ca ? 'CA:TRUE' : 'CA:FALSE', true))
      cert.add_extension(factory.create_extension('keyUsage', ca ? 'keyCertSign,cRLSign' : 'digitalSignature', true))
      unless ca
        cert.add_extension(factory.create_extension('extendedKeyUsage', 'serverAuth'))
        cert.add_extension(factory.create_extension('subjectAltName', "DNS:#{name}"))
      end
      cert.sign(issuer_key || key, OpenSSL::Digest.new('SHA256'))
      cert
    end
  end
end
PurchaseDemo::Setup.run! if $PROGRAM_NAME == __FILE__
