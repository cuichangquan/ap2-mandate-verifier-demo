# frozen_string_literal: true
require 'json'
require 'net/http'
require 'openssl'
require 'timeout'
require 'time'
require 'sqlite3'
require_relative 'tls'

module PurchaseDemo
  # Readiness is observational: it never issues approvals or resends purchases.
  # Each endpoint checks only local state, avoiding recursive dependency probes.
  class Readiness
    ROLES = %w[authority buyer seller].freeze
    PRIVATE = {
      'authority' => %w[signing_key.pem state.sqlite3 session_secret buyer_control.token seller_control.token],
      'buyer' => %w[signing_key.pem state.sqlite3 tls.key tls.crt buyer_control.token seller_a2a.token],
      'seller' => %w[signing_key.pem state.sqlite3 acceptance.sqlite3 tls.key tls.crt seller_control.token seller_a2a.token]
    }.freeze
    class Unavailable < StandardError; end
    class AuthenticationFailure < Unavailable; end

    def initialize(role:, state_dir: ENV.fetch('PURCHASE_STATE_DIR', '/state'), trust_dir: ENV.fetch('PURCHASE_TRUST_DIR', '/trust'), clock: -> { Time.now }, probe: nil)
      raise ArgumentError, 'invalid role' unless ROLES.include?(role)
      @role, @state, @trust, @clock, @probe = role, state_dir, trust_dir, clock, probe
    end

    def local
      now = @clock.call
      checks = []
      checks << check('initialization', File.file?(File.join(@trust, '.initialized')), 'preparing')
      checks << check('maintenance', !File.exist?(File.join(@trust, '.tls-rotation.json')), 'certificate_update_required')
      checks << check('files', valid_files?, 'preparing')
      checks << check('storage', storage_ready?, 'unreachable')
      checks << check('identity', identity_ready?, 'preparing')
      tls = TLS.status(role: @role, state_dir: @state, trust_dir: @trust, now: now)
      tls_ready = tls_ready?(tls)
      checks << check('tls', tls_ready, tls['status'] == 'preparing' ? 'preparing' : 'certificate_update_required')
      status = checks.find { |c| !c['ready'] }&.fetch('status') || 'ready'
      status = 'certificate_update_required' if checks.any? { |c| !c['ready'] && c['status'] == 'certificate_update_required' }
      {'role' => @role, 'status' => status, 'ready' => checks.all? { |c| c['ready'] },
       'checked_at' => now.utc.iso8601, 'checks' => checks, 'certificates' => tls['certificates'] || tls[:certificates] || [], 'tls' => tls}
    rescue StandardError
      {'role' => @role, 'status' => 'preparing', 'ready' => false, 'checked_at' => @clock.call.utc.iso8601,
       'checks' => [check('local_state', false, 'preparing')], 'certificates' => []}
    end

    def report
      result = local
      peers = case @role
      when 'authority' then %w[buyer seller]
      when 'buyer' then %w[seller]
      else []
      end
      dependencies = peers.to_h { |peer| [peer, @probe ? @probe.call(peer) : probe(peer, path: '/ready')] }
      result['dependencies'] = dependencies
      local_ready = result['ready']
      all_ready = local_ready && dependencies.values.all? { |peer| peer['ready'] }
      result['operations'] = if @role == 'authority'
        {'approve' => all_ready, 'provision' => all_ready, 'run' => all_ready,
         'status' => local_ready && dependencies.fetch('buyer')['ready'], 'recover' => local_ready && dependencies.fetch('buyer')['ready'], 'history' => true, 'diagnose' => true}
      elsif @role == 'buyer'
        {'provision' => local_ready, 'run' => all_ready, 'status' => all_ready, 'recover' => all_ready}
      else
        %w[provision offer purchase status recover].to_h { |op| [op, local_ready] }
      end
      result['ready'] = all_ready
      if local_ready && !all_ready
        result['status'] = dependencies.values.any? { |peer| peer['status'] == 'certificate_update_required' } ? 'certificate_update_required' : 'unreachable'
      end
      result
    end

    # Container health also checks the actual local listener. Endpoint handlers
    # use local/report, never healthcheck, so this cannot recursively call itself.
    def healthcheck
      result = report
      own = @probe ? @probe.call(@role) : probe(@role)
      result['listener'] = own
      unless own['ready']
        result['ready'] = false
        result['status'] = own['status'] unless result['status'] == 'certificate_update_required'
      end
      result
    end

    def require!(operation)
      raise Unavailable, 'required services are not ready' unless report.fetch('operations').fetch(operation.to_s, false)
      true
    end

    private

    def check(name, ready, failure) = {'name' => name, 'ready' => !!ready, 'status' => ready ? 'ready' : failure}

    def valid_files?
      PRIVATE.fetch(@role).all? do |name|
        path = File.join(@state, name)
        File.file?(path) && !File.symlink?(path) && File.size(path).positive? && File.readable?(path) && (File.stat(path).mode & 0o077).zero?
      end && %w[authority.pub.pem buyer.pub.pem seller.pub.pem ca.crt].all? do |name|
        path = File.join(@trust, name)
        File.file?(path) && !File.symlink?(path) && File.readable?(path) && File.size(path).positive?
      end
    rescue SystemCallError
      false
    end

    def identity_ready?
      private_key = OpenSSL::PKey.read(File.binread(File.join(@state, 'signing_key.pem')))
      public_key = OpenSSL::PKey.read(File.binread(File.join(@trust, "#{@role}.pub.pem")))
      return false unless private_key.private? && private_key.public_to_der == public_key.public_to_der
      PRIVATE.fetch(@role).grep(/\.token\z/).all? { |name| File.read(File.join(@state, name)).strip.match?(/\A[0-9a-f]{64}\z/) } &&
        (@role != 'authority' || File.read(File.join(@state, 'session_secret')).strip.match?(/\A[0-9a-f]{128}\z/))
    rescue StandardError
      false
    end

    def storage_ready?
      return false unless File.directory?(@state) && File.writable?(@state)
      names = @role == 'seller' ? %w[state.sqlite3 acceptance.sqlite3] : %w[state.sqlite3]
      names.all? do |name|
        path = File.join(@state, name)
        next false unless File.file?(path) && File.writable?(path)
        begin
          db = SQLite3::Database.new(path, flags: SQLite3::Constants::Open::READWRITE)
          db.busy_timeout = 100
          db.execute('BEGIN IMMEDIATE')
          valid = db.get_first_value('PRAGMA quick_check(1)') == 'ok'
          valid &&= db.get_first_value('PRAGMA user_version') == 1 if name == 'state.sqlite3'
          if name == 'state.sqlite3'
            db.execute('SELECT id, document FROM purchases LIMIT 0')
            db.execute('SELECT purchase_id, processor_key, document FROM processor LIMIT 0')
          else
            valid &&= db.get_first_value('PRAGMA user_version') == 1
            %w[ap2_store ap2_approvals ap2_attempts].each { |table| db.execute("SELECT * FROM #{table} LIMIT 0") }
            valid &&= db.get_first_value('SELECT count(*) FROM ap2_store') == 1
          end
          valid
        ensure
          db&.execute('ROLLBACK') rescue nil
          db&.close
        end
      end
    rescue StandardError
      false
    end

    def tls_ready?(tls)
      # TLS.status is an allow-list, never treat an unknown state as healthy.
      status = tls['status'] || tls[:status]
      status.to_s == 'ready'
    end

    def probe(peer, path: '/health')
      Timeout.timeout(2.5) do
        http = Net::HTTP.new(peer == 'authority' ? 'localhost' : peer, peer == 'authority' ? 3100 : 3443, nil)
        unless peer == 'authority'
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          http.verify_hostname = true
          http.ca_file = File.join(@trust, 'ca.crt')
        end
        http.open_timeout = 1
        http.read_timeout = 1
        http.write_timeout = 1
        http.max_retries = 0
        body = +''
        response_status = nil
        certificate = nil
        http.start do |connection|
          certificate = connection.peer_cert unless peer == 'authority'
          request = Net::HTTP::Get.new(path)
          if path == '/ready'
            token_name = @role == 'authority' ? "#{peer}_control.token" : 'seller_a2a.token'
            token = File.read(File.join(@state, token_name)).strip
            raise Unavailable unless token.match?(/\A[0-9a-f]{64}\z/)
            request['Authorization'] = "Bearer #{token}"
          end
          request['Accept'] = 'application/json'
          request['Accept-Encoding'] = 'identity'
          connection.request(request) do |response|
            response_status = response.code.to_i
            raise AuthenticationFailure if response_status == 401
            raise Unavailable unless [200, 503].include?(response_status) && response['Content-Type'].to_s.split(';').first == 'application/json'
            response.read_body { |part| raise(Unavailable) if body.bytesize + part.bytesize > 16_384; body << part }
          end
        end
        value = JSON.parse(body, max_nesting: 16)
        raise Unavailable unless value.is_a?(Hash) && value['role'] == peer && [true, false].include?(value['ready'])
        status = %w[ready preparing unreachable certificate_update_required].include?(value['status']) ? value['status'] : 'unreachable'
        {'role' => peer, 'ready' => response_status == 200 && value['ready'] && status == 'ready', 'status' => status,
         'certificates' => value['certificates'] || {}, 'checks' => value['checks'] || [], 'tls' => value['tls'] || {},
         'peer_expires_at' => certificate&.not_after&.utc&.iso8601, 'peer_remaining_seconds' => certificate && (certificate.not_after - @clock.call).to_i}
      end
    rescue AuthenticationFailure
      {'role' => peer, 'ready' => false, 'status' => 'unreachable', 'reason' => 'authentication_failed'}
    rescue OpenSSL::SSL::SSLError => error
      verification = error.message.include?('certificate verify failed')
      {'role' => peer, 'ready' => false, 'status' => verification ? 'certificate_update_required' : 'unreachable',
       'reason' => verification ? 'tls_verification_failed' : 'tls_handshake_failed'}
    rescue StandardError
      {'role' => peer, 'ready' => false, 'status' => 'unreachable', 'reason' => 'connection_failed'}
    end
  end
end

if $PROGRAM_NAME == __FILE__
  role = ARGV.find { |arg| PurchaseDemo::Readiness::ROLES.include?(arg) } || ENV.fetch('PURCHASE_ROLE', 'authority')
  report = PurchaseDemo::Readiness.new(role: role).healthcheck
  if ARGV.include?('--json')
    puts JSON.generate(report)
  else
    labels = {'ready' => 'Ready / 利用可能', 'preparing' => 'Preparing / 準備中',
      'unreachable' => 'Cannot connect / 接続できない', 'certificate_update_required' => 'Certificate update required / 証明書の更新が必要'}
    puts "#{role}: #{labels.fetch(report.fetch('status'))}"
    report.fetch('dependencies', {}).each { |peer, value| puts "#{peer}: #{labels.fetch(value.fetch('status'))}" }
    puts 'Diagnostics only; no purchase was sent. / 診断のみ。購入は送信していません。'
    puts 'Run the diagnose command for certificate details. / 証明書の詳細は diagnose コマンドで確認してください。' unless report['ready']
  end
  exit(report['ready'] ? 0 : 1)
end
