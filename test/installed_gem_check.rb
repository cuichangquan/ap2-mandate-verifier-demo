# frozen_string_literal: true
# Normal installed official Gem only; no build, source overlay or network.
require "ap2_mandate_verifier"
require "rubygems/package"
require "digest"
require "json"
require "tmpdir"

artifact = ARGV.fetch(0, "vendor/cache/ap2_mandate_verifier-1.1.0.gem")
expected_sha = "4c64cf5b6c61ae4395577828093a6f4022c35cf18b6ad1bcfcb9f95fbb4f43c9"
abort "official Gem identity mismatch" unless File.size(artifact) == 115_200 &&
  Digest::SHA256.file(artifact).hexdigest == expected_sha
package = Gem::Package.new(artifact)
package.verify
spec = Gem.loaded_specs.fetch("ap2_mandate_verifier")
root = File.realpath(File.expand_path("..", __dir__))
abort "normal installed Gem required" unless spec.version.to_s == "1.1.0" &&
  !File.realpath(spec.full_gem_path).start_with?(root + "/")
files = package.contents.sort
abort "payload inventory mismatch" unless files.size == 38 && files == package.spec.files.sort &&
  package.spec.name == "ap2_mandate_verifier" && package.spec.version.to_s == "1.1.0" &&
  package.spec.extensions.empty?
dependencies = {"base64" => "= 0.3.0", "digest" => "= 3.2.1", "json" => "= 2.19.9",
  "jwt" => "= 3.3.0", "openssl" => "= 4.0.2"}
[package.spec, spec].each do |value|
  abort "dependency or Ruby requirement mismatch" unless
    value.runtime_dependencies.to_h { |d| [d.name, d.requirement.to_s] } == dependencies &&
    value.required_ruby_version == Gem::Requirement.new(">= 3.4.12", "< 4.1")
end
Dir.mktmpdir("official-demo-gem-") do |directory|
  package.extract_files(directory)
  files.each do |path|
    abort "archive/installed payload mismatch" unless
      File.binread(File.join(directory, path)) == File.binread(File.join(spec.full_gem_path, path))
  end
end
puts JSON.generate(version: spec.version.to_s, artifact_bytes: File.size(artifact),
  artifact_sha256: expected_sha, payloads: files.size,
  archive_installed_payloads_match: true, installed_outside_demo: true)
