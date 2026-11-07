# frozen_string_literal: true
require "bundler/setup"
require "rack"
require "json"
require "openssl"
require_relative "runtime"
module PurchaseDemo
  class BuyerApplication
    def call(env)
      return response(200, {"status" => "ok"}) if env["REQUEST_METHOD"] == "GET" && env["PATH_INFO"] == "/health"
      return response(404, {"error" => "not_found"}) unless env["REQUEST_METHOD"] == "POST" && env["PATH_INFO"] == "/control"
      token = File.binread(File.join(Runtime.state_dir, "buyer_control.token")).strip
      supplied = env["HTTP_AUTHORIZATION"].to_s
      expected = "Bearer #{token}"
      return response(401, {"error" => "unauthorized"}) unless supplied.bytesize == expected.bytesize && OpenSSL.fixed_length_secure_compare(supplied, expected)
      return response(415, {"error" => "invalid_request"}) unless env["CONTENT_TYPE"].to_s.split(";").first == "application/json"
      body = env.fetch("rack.input").read(131_073)
      return response(413, {"error" => "invalid_request"}) if body.bytesize > 131_072
      payload = JSON.parse(body, max_nesting: 32)
      return response(400, {"error" => "invalid_request"}) unless payload.instance_of?(Hash)
      response(200, Runtime.buyer.control(payload))
    rescue StandardError
      response(503, {"error" => "purchase_unavailable"})
    end
    def response(status, payload) = [status, {"content-type" => "application/json", "cache-control" => "no-store"}, [JSON.generate(payload)]]
  end
end
