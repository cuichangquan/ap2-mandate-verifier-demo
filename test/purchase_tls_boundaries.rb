# frozen_string_literal: true
# Run in the buyer container against the real, separate seller TLS process.
# This is deliberately not a transport stub or an in-process HTTP server.
require 'bundler/setup'
require 'net/http'
require 'openssl'
require 'resolv'
require 'json'
require 'a2a-rails'

module PurchaseTLSBoundaries
  module_function

  def check(condition, label)
    abort "FAIL: #{label}" unless condition
    puts "PASS: #{label}"
  end

  def tls_request(host:, store:, path: '/health', token: nil)
    http = Net::HTTP.new(host, 3443, nil)
    # A wrong-host probe uses the SAME seller socket, not nonexistent DNS.
    http.ipaddr = Resolv.getaddress('seller')
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.verify_hostname = true
    http.cert_store = store
    http.open_timeout = 2
    http.read_timeout = 2
    http.write_timeout = 2
    http.max_retries = 0
    request = token ? Net::HTTP::Post.new(path) : Net::HTTP::Get.new(path)
    if token
      request['Authorization'] = "Bearer #{token}"
      request['Content-Type'] = 'application/json'
      request.body = '{}'
    end
    http.request(request)
  end

  def must_reject_tls(label)
    begin
      yield
    rescue OpenSSL::SSL::SSLError
      puts "PASS: #{label}"
      return
    end
    abort "FAIL: #{label}"
  end

  def run!
    state, trust = ENV.fetch('PURCHASE_STATE_DIR'), ENV.fetch('PURCHASE_TRUST_DIR')
    own = OpenSSL::PKey.read(File.read(File.join(state, 'signing_key.pem')))
    buyer = OpenSSL::PKey.read(File.read(File.join(trust, 'buyer.pub.pem')))
    issuer = OpenSSL::PKey.read(File.read(File.join(trust, 'authority.pub.pem')))
    check(own.public_to_der == buyer.public_to_der && own.public_to_der != issuer.public_to_der,
      'buyer has Agent private key, not Issuer private key')
    check(!File.exist?(File.join(state, 'seller_control.token')) &&
      !File.exist?('/state-authority') && !File.exist?('/state-seller'),
      'buyer cannot access seller-control credential or other role volumes')
    check(Dir.glob(File.join(trust, '*')).none? { |f| File.file?(f) && File.read(f).include?('PRIVATE KEY') },
      'shared trust contains no private keys')

    correct = OpenSSL::X509::Store.new
    correct.add_cert(OpenSSL::X509::Certificate.new(File.read(File.join(trust, 'ca.crt'))))
    response = tls_request(host: 'seller', store: correct)
    check(response.code == '200' && JSON.parse(response.body).fetch('role') == 'seller',
      'real seller TLS accepts trusted CA and correct hostname')

    # An empty explicit store trusts no CA, including the demo CA.
    must_reject_tls('untrusted CA fails TLS verification') do
      tls_request(host: 'seller', store: OpenSSL::X509::Store.new)
    end
    must_reject_tls('wrong hostname fails against the same real seller socket') do
      tls_request(host: 'wrong-seller.invalid', store: correct)
    end
    token = File.read(File.join(state, 'seller_a2a.token')).strip
    response = tls_request(host: 'seller', store: correct, path: '/control', token: token)
    check(response.code == '401', 'buyer A2A bearer cannot authorize seller control')

    ['127.0.0.1', Resolv.getaddress('seller')].each_with_index do |address, index|
      policy = A2A::Rails::Client::OutboundPolicy.new(
        allowed_origins: ['https://seller.example:3443'], resolver: ->(_host) { [address] })
      begin
        policy.resolve!('https://seller.example:3443/.well-known/agent-card.json')
        abort 'FAIL: production SSRF policy allowed a private destination'
      rescue A2A::Rails::Client::OutboundPolicy::RejectedTarget => error
        check(error.reason == :blocked_ip,
          index.zero? ? 'unchanged production SSRF policy rejects loopback' : 'unchanged production SSRF policy rejects private Docker address')
      end
    end
    puts 'PASS: live separate-process TLS and role boundary checks completed'
  rescue StandardError
    # Do not echo paths, tokens, wire payloads or nested transport exceptions.
    abort 'FAIL: live TLS boundary probe could not complete'
  end
end
PurchaseTLSBoundaries.run!
