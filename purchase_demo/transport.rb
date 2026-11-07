# frozen_string_literal: true
require 'json'
require 'net/http'
require 'openssl'
require 'securerandom'
require 'timeout'

module PurchaseDemo
  # Application-only Docker demo transport. Never changes a2a-rails policies.
  # The caller cannot supply origins, ports, redirects, or arbitrary paths.
  class Transport
    class Error < StandardError
      attr_reader :code
      def initialize(message = 'transport unavailable', code: :unavailable)
        @code = code
        super(message)
      end
    end
    ORIGINS = { 'seller' => 'https://seller:3443', 'buyer' => 'https://buyer:3443' }.freeze
    MAX_BYTES = 131_072

    def initialize(role:, state_dir: ENV.fetch('PURCHASE_STATE_DIR', '/state'), trust_dir: ENV.fetch('PURCHASE_TRUST_DIR', '/trust'))
      raise Error, 'invalid role' unless %w[authority buyer].include?(role)
      @role, @state_dir, @trust_dir = role, state_dir, trust_dir
    end

    def request(service:, path:, payload:)
      service = service.to_s
      raise Error, 'route not allowed' unless @role == 'authority' && ORIGINS.key?(service) && path == '/control'
      exchange(service, path, payload, "#{service}_control.token")
    end

    def a2a(command:, payload:)
      raise Error, 'route not allowed' unless @role == 'buyer'
      raise Error, 'invalid command' unless command.is_a?(String) && command.match?(/\A[a-z_]{1,32}\z/) && payload.is_a?(Hash)
      card = exchange('seller', '/.well-known/agent-card.json', nil, 'seller_a2a.token')
      supported = card['supportedInterfaces']
      unless supported.is_a?(Array) && supported.any? { |i| i.is_a?(Hash) && i['url'] == "#{ORIGINS.fetch('seller')}/a2a" && i['protocolBinding'] == 'JSONRPC' && i['protocolVersion'] == '1.0' }
        raise Error, 'unsupported seller interface'
      end
      id = SecureRandom.uuid
      result = exchange('seller', '/a2a', {
        'jsonrpc' => '2.0', 'id' => id, 'method' => 'SendMessage',
        'params' => { 'message' => {
          'messageId' => SecureRandom.uuid, 'role' => 'ROLE_USER',
          'parts' => [{ 'text' => command }],
          'metadata' => { 'purchase_demo' => payload }
        } }
      }, 'seller_a2a.token')
      unless result['jsonrpc'] == '2.0' && result['id'] == id && !result.key?('error') && result['result'].is_a?(Hash)
        raise Error, 'seller protocol failure'
      end
      task = result['result']['task']
      unless task.is_a?(Hash) && task.dig('status', 'state') == 'TASK_STATE_COMPLETED'
        raise Error, 'seller task not completed'
      end
      parts = task.dig('artifacts', 0, 'parts')
      data = parts.is_a?(Array) && parts.first.is_a?(Hash) && parts.first['data']
      raise Error, 'invalid seller artifact' unless data.is_a?(Hash)
      data
    end

    private

    def exchange(service, path, payload, token_file)
      raise Error, 'invalid payload' unless payload.nil? || payload.is_a?(Hash)
      body = payload.nil? ? nil : JSON.generate(payload, max_nesting: 32, allow_nan: false)
      raise Error, 'request too large' if body && body.bytesize > MAX_BYTES
      token = File.read(File.join(@state_dir, token_file)).strip
      raise Error, 'invalid credential' unless token.match?(/\A[0-9a-f]{64}\z/)
      uri = URI(ORIGINS.fetch(service))
      Timeout.timeout(8) do
        http = Net::HTTP.new(uri.host, uri.port, nil) # Ignore environment proxies.
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.verify_hostname = true
        http.ca_file = File.join(@trust_dir, 'ca.crt')
        http.open_timeout = 2
        http.read_timeout = 2
        http.write_timeout = 2
        http.max_retries = 0
        request = (body ? Net::HTTP::Post : Net::HTTP::Get).new(path)
        request['Authorization'] = "Bearer #{token}"
        request['Accept'] = 'application/json'
        request['Accept-Encoding'] = 'identity'
        request['Content-Type'] = 'application/json'
        request['A2A-Version'] = '1.0'
        request.body = body if body
        response_body = +''
        http.start do |connection|
          connection.request(request) do |response|
            raise Error, 'remote request failed' unless response.code.to_i == 200
            raise Error, 'invalid response type' unless response['Content-Type'].to_s.split(';').first == 'application/json'
            raise Error, 'encoded response rejected' unless ['', 'identity'].include?(response['Content-Encoding'].to_s)
            length = response['Content-Length']
            raise Error, 'invalid response size' if length && (!length.match?(/\A\d+\z/) || length.to_i > MAX_BYTES)
            response.read_body do |chunk|
              raise Error, 'response too large' if response_body.bytesize + chunk.bytesize > MAX_BYTES
              response_body << chunk
            end
            raise Error, 'truncated response' if length && response_body.bytesize != length.to_i
          end
        end
        value = JSON.parse(response_body, max_nesting: 32)
        raise Error, 'invalid response' unless value.is_a?(Hash)
        value
      end
    rescue Error
      raise
    rescue Net::ReadTimeout, Net::OpenTimeout, Timeout::Error
      raise Error.new('transport timeout; outcome may be uncertain', code: :timeout), cause: nil
    rescue StandardError
      # Neither remote bodies nor nested exceptions may escape to logs/UI.
      raise Error.new('transport unavailable; outcome may be uncertain'), cause: nil
    end
  end
end
