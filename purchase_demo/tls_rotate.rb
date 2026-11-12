# frozen_string_literal: true
require 'json'
require 'digest'
require 'fileutils'
require_relative 'setup'
require_relative 'tls'

module PurchaseDemo
  # Offline, forward-recoverable transaction. Staged private TLS keys remain only
  # in their role's private volume. The CA private key is never persisted.
  class TLSRotation
    FILES = {'trust' => ['ca.crt', 'buyer.crt', 'seller.crt'], 'buyer' => ['tls.key', 'tls.crt'], 'seller' => ['tls.key', 'tls.crt']}.freeze
    def initialize(dirs:, trust:, fault: nil)
      @dirs, @trust, @fault = dirs, trust, fault
    end

    def rotate!(restart: false)
      File.umask(0o077)
      lock = File.join(@trust, '.tls-rotation.lock')
      raise 'unsafe rotation lock' if File.symlink?(lock)
      File.open(lock, File::RDWR | File::CREAT, 0o600) do |file|
        raise 'TLS rotation already running' unless file.flock(File::LOCK_EX | File::LOCK_NB)
        # Existing setup must be complete; expiry is deliberately not rejected.
        Setup.validate_existing!(dirs: @dirs, trust: @trust)
        prepare! if restart || !File.exist?(journal)
        manifest = JSON.parse(File.binread(journal))
        validate_stage!(manifest)
        entries.each_with_index do |(role, name), index|
          destination = File.join(directory(role), name)
          raise 'unsafe TLS destination' if File.symlink?(destination)
          atomic_write(destination, File.binread(stage(role, name)), mode: role == 'trust' ? 0o644 : 0o600)
          @fault&.call(index + 1)
        end
        %w[buyer seller].each do |role|
          result = TLS.status(role: role, state_dir: @dirs.fetch(role), trust_dir: @trust)
          raise 'installed TLS set failed validation' unless (result.fetch('reasons') - ['rotation_pending']).empty?
        end
        File.unlink(journal)
        sync_dir(@trust)
        cleanup_stage!
        {'status' => 'rotated', 'preserved' => 'all non-TLS state', 'next' => 'restart and verify HTTPS readiness'}
      end
    end

    private

    def journal = File.join(@trust, TLS::PENDING)
    def directory(role) = role == 'trust' ? @trust : @dirs.fetch(role)
    def stage(role, name) = File.join(directory(role), ".tls-next-#{name}")
    def entries = FILES.flat_map { |role, names| names.map { |name| [role, name] } }

    def prepare!
      cleanup_stage!
      ca_key = OpenSSL::PKey::EC.generate('prime256v1')
      ca = Setup.certificate('purchase-demo-ca', ca_key, nil, nil, ca: true)
      atomic_write(stage('trust', 'ca.crt'), ca.to_pem, mode: 0o644)
      %w[buyer seller].each do |role|
        key = OpenSSL::PKey::EC.generate('prime256v1')
        cert = Setup.certificate(role, key, ca, ca_key)
        atomic_write(stage(role, 'tls.key'), key.private_to_pem)
        atomic_write(stage(role, 'tls.crt'), cert.to_pem)
        atomic_write(stage('trust', "#{role}.crt"), cert.to_pem, mode: 0o644)
      end
      hashes = entries.to_h { |role, name| ["#{role}/#{name}", Digest::SHA256.file(stage(role, name)).hexdigest] }
      atomic_write(journal, JSON.generate({'version' => 1, 'sha256' => hashes}), mode: 0o644)
      @fault&.call(0)
    end

    def validate_stage!(manifest)
      expected = entries.map { |role, name| "#{role}/#{name}" }.sort
      raise 'invalid TLS rotation journal' unless manifest['version'] == 1 && manifest['sha256'].is_a?(Hash) && manifest['sha256'].keys.sort == expected
      entries.each do |role, name|
        path = stage(role, name)
        raise 'damaged TLS rotation stage; keep services stopped' if File.symlink?(path) || Digest::SHA256.file(path).hexdigest != manifest['sha256'].fetch("#{role}/#{name}")
      end
      ca = TLS.read_certificate(stage('trust', 'ca.crt'))
      raise 'invalid staged CA' unless ca.verify(ca.public_key)
      %w[buyer seller].each do |role|
        cert = TLS.read_certificate(stage(role, 'tls.crt'))
        key = OpenSSL::PKey.read(File.binread(stage(role, 'tls.key')))
        raise 'inconsistent public certificate copy' unless File.binread(stage(role, 'tls.crt')) == File.binread(stage('trust', "#{role}.crt"))
        store = OpenSSL::X509::Store.new
        store.add_cert(ca)
        store.purpose = OpenSSL::X509::PURPOSE_SSL_SERVER
        raise 'invalid staged TLS set' unless cert.check_private_key(key) && store.verify(cert) && OpenSSL::SSL.verify_certificate_identity(cert, role)
      end
    end

    def cleanup_stage!
      entries.each do |role, name|
        path = stage(role, name)
        File.unlink(path) if File.exist?(path) || File.symlink?(path)
      end
    end

    def atomic_write(path, data, mode: 0o600)
      temp = "#{path}.tmp-#{SecureRandom.hex(8)}"
      File.open(temp, File::WRONLY | File::CREAT | File::EXCL, mode) do |file|
        file.write(data)
        file.flush
        file.fsync
      end
      File.chown(10001, 10001, temp) if Process.uid.zero?
      File.rename(temp, path)
      sync_dir(File.dirname(path))
    ensure
      File.unlink(temp) if temp && File.exist?(temp)
    end

    def sync_dir(path)
      File.open(path, File::RDONLY) { |dir| dir.fsync }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  dirs = PurchaseDemo::Setup::ROLES.to_h { |role| [role, "/state-#{role}"] }
  if ARGV == ['--diagnose']
    report = dirs.to_h { |role, state| [role, PurchaseDemo::TLS.status(role: role, state_dir: state, trust_dir: '/trust')] }
    explanations = {
      'expiring' => ['Certificate expires within 48 hours; plan a stopped-service TLS rotation.', '48時間以内に期限切れになります。停止を伴う証明書更新を計画してください。'],
      'expired' => ['Certificate expired; rotate TLS before purchase operations.', '証明書の期限切れです。購入操作の前にTLS証明書を更新してください。'],
      'not_yet_valid' => ['Certificate is not yet valid; check time and certificate dates.', '証明書の有効期間前です。時刻と証明書の日付を確認してください。'],
      'ca_mismatch' => ['CA and service certificate do not match; rotate the complete TLS set.', 'CAとサービス証明書が不整合です。TLS一式を更新してください。'],
      'key_mismatch' => ['TLS certificate and private key differ; rotate the complete TLS set.', 'TLS証明書と秘密鍵が不一致です。TLS一式を更新してください。'],
      'hostname_mismatch' => ['Service hostname verification failed; rotate the complete TLS set.', 'サービスのホスト名検証に失敗しました。TLS一式を更新してください。'],
      'invalid_chain' => ['Certificate chain validation failed; inspect the other diagnostic reasons.', '証明書チェーン検証に失敗しました。他の診断理由を確認してください。'],
      'rotation_pending' => ['Interrupted rotation; keep services stopped and run recovery.', '更新が中断されています。サービスを停止したまま復旧してください。'],
      'missing_tls_files' => ['TLS files are missing; inspect init status. Never reset existing purchase volumes.', 'TLSファイルがありません。初期化状態を確認してください。既存の購入volumeをリセットしないでください。'],
      'invalid_tls_material' => ['TLS material could not be parsed or inspected; use stopped-service diagnostics and recovery.', 'TLS情報を読み取れません。停止状態で診断と復旧を実施してください。']
    }
    report.each_value do |result|
      result['guidance'] = result['reasons'].to_h { |reason| [reason, {'en' => explanations.fetch(reason)[0], 'ja' => explanations.fetch(reason)[1]}] }
    end
    puts JSON.pretty_generate({'certificates' => report, 'next_en' => 'Run sh bin/purchase-demo status for live TLS readiness. If renewal is needed, run sh bin/purchase-demo rotate. Purchase data is retained.',
      'next_ja' => '実通信の準備確認は sh bin/purchase-demo status。証明書更新は sh bin/purchase-demo rotate。購入データは保持されます。'})
    exit(report.values.all? { |r| r['status'] == 'ready' } ? 0 : 1)
  end
  abort 'Run through the stopped-service maintenance wrapper.' unless [['--services-stopped'], ['--services-stopped', '--restart-staging']].include?(ARGV)
  begin
    puts JSON.generate(PurchaseDemo::TLSRotation.new(dirs: dirs, trust: '/trust').rotate!(restart: ARGV.include?('--restart-staging')))
  rescue StandardError
    warn 'TLS rotation incomplete. Keep services stopped; rerun rotation or use documented staging recovery. Purchase data was not reset. / 更新未完了。停止状態で再実行または復旧手順を実施してください。購入データは保持されています。'
    exit 1
  end
end
