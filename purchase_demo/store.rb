# frozen_string_literal: true
require "json"
require "sqlite3"
require "fileutils"
require "ap2_mandate_verifier"

module PurchaseDemo
  # Role-private application records. Normal boot never creates a missing DB.
  class Store
    class Unavailable < StandardError; end
    ID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
    def self.bootstrap(role:, state_dir:)
      FileUtils.mkdir_p(state_dir, mode: 0o700)
      path = File.join(state_dir, "state.sqlite3")
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.fsync }
      db = SQLite3::Database.new(path)
      db.execute("CREATE TABLE purchases (id TEXT PRIMARY KEY, document TEXT NOT NULL)")
      db.execute("CREATE TABLE processor (purchase_id TEXT PRIMARY KEY, processor_key TEXT UNIQUE NOT NULL, document TEXT NOT NULL)")
      db.execute("PRAGMA user_version=1")
      db.close
      if role == "seller"
        ledger = AP2MandateVerifier::PaymentAcceptance::SQLiteStore.create(path: File.join(state_dir, "acceptance.sqlite3"))
        ledger.close
      end
    end

    def initialize(state_dir: ENV.fetch("PURCHASE_STATE_DIR"))
      @dir = state_dir
      @path = File.join(@dir, "state.sqlite3")
      raise Unavailable unless File.file?(@path) && (File.stat(@path).mode & 0o077).zero?
      with_db { |db| raise Unavailable unless db.get_first_value("PRAGMA user_version") == 1 }
    end

    def read(id)
      validate_id(id)
      with_db { |db| decode(db.get_first_value("SELECT document FROM purchases WHERE id=?", [id])) }
    end

    def list
      with_db { |db| db.execute("SELECT document FROM purchases ORDER BY rowid DESC LIMIT 200").map { |r| decode(r[0]) } }
    end

    def save_once(id, document)
      validate_id(id)
      transaction do |db|
        old = decode(db.get_first_value("SELECT document FROM purchases WHERE id=?", [id]))
        next old if old
        raise Unavailable if db.get_first_value("SELECT count(*) FROM purchases") >= 200
        db.execute("INSERT INTO purchases(id,document) VALUES (?,?)", [id, encode(document)])
        document
      end
    end

    def update(id)
      validate_id(id)
      transaction do |db|
        old = decode(db.get_first_value("SELECT document FROM purchases WHERE id=?", [id]))
        raise Unavailable unless old
        result = yield old
        db.execute("UPDATE purchases SET document=? WHERE id=?", [encode(result), id])
        result
      end
    end

    # Prevent overlapping work in one role, including separate Ruby processes.
    # This is supplementary; SDK acceptance CAS and processor UNIQUE constraints
    # remain authoritative if the caller omits this serialization.
    def lock(id)
      validate_id(id)
      File.open(File.join(@dir, "#{id}.lock"), File::RDWR | File::CREAT, 0o600) do |f|
        f.flock(File::LOCK_EX)
        yield
      ensure
        f.flock(File::LOCK_UN)
      end
    end

    def processor(id)
      validate_id(id)
      with_db { |db| decode(db.get_first_value("SELECT document FROM processor WHERE purchase_id=?", [id])) }
    end

    # The mock side effect and result are one durable local transaction. This
    # models a queryable idempotent PSP; it does NOT claim external exactly-once.
    def process_once(id:, processor_key:, result:)
      validate_id(id)
      transaction do |db|
        row = db.get_first_row("SELECT processor_key,document FROM processor WHERE purchase_id=?", [id])
        if row
          raise Unavailable unless row[0] == processor_key
          next decode(row[1])
        end
        value = result.merge("execution_count" => 1)
        db.execute("INSERT INTO processor(purchase_id,processor_key,document) VALUES (?,?,?)", [id, processor_key, encode(value)])
        value
      end
    end

    private
    def validate_id(id)
      raise ArgumentError, "invalid purchase id" unless id.is_a?(String) && ID.match?(id)
    end
    def encode(value)
      text = JSON.generate(value)
      raise Unavailable if text.bytesize > 262_144
      text
    end
    def decode(value) = value && JSON.parse(value, max_nesting: 32)
    def with_db
      db = SQLite3::Database.new(@path, flags: SQLite3::Constants::Open::READWRITE)
      db.busy_timeout = 5000
      db.execute("PRAGMA synchronous=FULL")
      yield db
    rescue SQLite3::Exception, JSON::ParserError
      raise Unavailable, "purchase state unavailable", cause: nil
    ensure
      db&.close
    end
    def transaction
      with_db do |db|
        db.execute("BEGIN IMMEDIATE")
        result = yield db
        db.execute("COMMIT")
        result
      rescue StandardError
        db.execute("ROLLBACK") rescue nil
        raise
      end
    end
  end
end
