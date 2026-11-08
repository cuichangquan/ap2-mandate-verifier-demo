# frozen_string_literal: true
module PurchaseDemo
  # The only runtime component with the Provider key. Browser requests never
  # supply approval contents or signing inputs: only a confirmed fixed scenario.
  class Authority < Role
    def transport = @transport ||= Transport.new(role: "authority")
    def approve(id:, scenario:)
      raise BoundaryError unless SCENARIOS.include?(scenario) && Store::ID.match?(id)
      @store.lock(id) do
        row = @store.read(id)
        if row
          raise BoundaryError unless row.fetch("scenario") == scenario
        else
          approval = Protocol.approval(approval_id: id, provider_key: key, agent_public_key_pem: keys.fetch(:agent), now: now)
          row = @store.save_once(id, {"id" => id, "scenario" => scenario, "approval" => approval})
        end
        provision(row)
      end
      id
    rescue Transport::Error
      id # Protected original approval survives; run can resume provisioning.
    end
    def provision(row)
      payload = {"purchase_id" => row.fetch("id"), "scenario" => row.fetch("scenario"), "approval" => row.fetch("approval")}
      transport.request(service: "seller", path: "/control", payload: payload)
      transport.request(service: "buyer", path: "/control", payload: payload.merge("command" => "provision"))
      @store.update(row.fetch("id")) { |r| r.merge("provisioned" => true) }
    end
    def run(id:)
      row = record(id)
      provision(row) unless row["provisioned"]
      save_summary(id, transport.request(service: "buyer", path: "/control", payload: {"command" => "run", "purchase_id" => id}))
    rescue Transport::Error
      @store.update(id) { |r| r.merge("summary" => summary(r).merge("payment_status" => "response_unknown",
        "reason" => "authority_unreachable")) }
      status(id: id)
    end
    def recover(id:)
      record(id)
      save_summary(id, transport.request(service: "buyer", path: "/control", payload: {"command" => "recover", "purchase_id" => id}))
    rescue Transport::Error
      summary(record(id))
    end
    def status(id:)
      row = record(id)
      if row["provisioned"]
        save_summary(id, transport.request(service: "buyer", path: "/control", payload: {"command" => "status", "purchase_id" => id}))
      else
        summary(row)
      end
    rescue Transport::Error
      summary(record(id))
    end
    def list = @store.list.map { |row| summary(row) }
    def save_summary(id, result)
      sanitized = result.fetch("summary").slice("offer", "ap2_status", "app_status", "payment_status", "receipt_status", "execution_count", "reason")
      summary(@store.update(id) { |r| r.merge("summary" => sanitized) })
    end
  end
end
