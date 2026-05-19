require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "spec_helper"))
require 'chef/knife/ec_error_handler'
require 'chef/knife/ec_backup'
require 'chef/knife/ec_restore'
require 'chef/chef_fs/config'
require 'chef/chef_fs/file_system'

# Contract/golden-file tests for EcErrorHandler JSON output.
#
# These tests verify that the error file schema remains stable across
# code changes. If the schema changes intentionally, update the golden
# fixture at spec/fixtures/golden/error_handler_schema.json.
describe Chef::Knife::EcErrorHandler, "contract" do
  GOLDEN_PATH = File.expand_path(
    File.join(File.dirname(__FILE__), "..", "..", "fixtures", "golden", "error_handler_schema.json")
  )

  let(:golden_schema) { JSON.parse(File.read(GOLDEN_PATH)) }
  let(:dest_dir) { Dir.mktmpdir }

  before(:each) do
    allow(Time).to receive(:now).and_return(Time.new(1988, 04, 17, 0, 0, 0, "+00:00"))
    @handler = described_class.new(dest_dir, Chef::Knife::EcBackup, suppress_exit: true)
  end

  after(:each) do
    FileUtils.rm_rf(dest_dir)
  end

  def parse_error_entries(file)
    # The error handler appends pretty-printed JSON objects directly concatenated.
    # Format: {...}{...} — no separator between closing } and opening {.
    content = File.read(file)
    # Split on }{ boundary, preserving braces on each side.
    parts = content.split(/\}\{/)
    parts.map.with_index do |part, i|
      json = if parts.length == 1
               part
             elsif i == 0
               part + "}"
             elsif i == parts.length - 1
               "{" + part
             else
               "{" + part + "}"
             end
      JSON.parse(json)
    end
  end

  def validate_entry_against_schema(entry, schema_name)
    schema = golden_schema[schema_name]
    raise "Unknown schema: #{schema_name}" unless schema

    # Verify all required keys are present
    schema["required_keys"].each do |key|
      expect(entry).to have_key(key), "Missing required key '#{key}' in #{schema_name} output"
    end

    # Verify types match
    schema["types"].each do |key, expected_type|
      next unless entry.key?(key)
      value = entry[key]

      if expected_type.is_a?(Array)
        # Multiple allowed types (e.g., ["array", "null"])
        valid = expected_type.any? { |t| value_matches_type?(value, t) }
        expect(valid).to be(true),
          "Key '#{key}' has value #{value.inspect} but expected one of #{expected_type} in #{schema_name}"
      else
        expect(value_matches_type?(value, expected_type)).to be(true),
          "Key '#{key}' has value #{value.inspect} but expected #{expected_type} in #{schema_name}"
      end
    end
  end

  def value_matches_type?(value, type_name)
    case type_name
    when "string"  then value.is_a?(String)
    when "boolean" then value == true || value == false
    when "array"   then value.is_a?(Array)
    when "null"    then value.nil?
    when "integer" then value.is_a?(Integer)
    else false
    end
  end

  context "HTTP error output schema" do
    it "matches the golden schema for http_error" do
      status = double("status", code: "500")
      ex = Net::HTTPServerException.new("I'm not real!", status)
      @handler.add(ex)

      entries = parse_error_entries(@handler.err_file)
      expect(entries.length).to eq(1)
      validate_entry_against_schema(entries[0], "http_error")
    end

    it "includes the expected example values" do
      status = double("status", code: "500")
      ex = Net::HTTPServerException.new("I'm not real!", status)
      @handler.add(ex)

      entries = parse_error_entries(@handler.err_file)
      entry = entries[0]
      example = golden_schema["http_error"]["example"]

      expect(entry["message"]).to eq(example["message"])
      expect(entry["exception"]).to eq(example["exception"])
      expect(entry["transient"]).to eq(example["transient"])
      expect(entry["http_code"]).to eq(example["http_code"])
    end
  end

  context "ChefFS NotFoundError output schema" do
    it "matches the golden schema for cheffs_not_found_error" do
      ex = Chef::ChefFS::FileSystem::NotFoundError.new('/boop', 'The exception', 'The reason')
      @handler.add(ex)

      entries = parse_error_entries(@handler.err_file)
      expect(entries.length).to eq(1)
      validate_entry_against_schema(entries[0], "cheffs_not_found_error")
    end

    it "includes the expected example values" do
      ex = Chef::ChefFS::FileSystem::NotFoundError.new('/boop', 'The exception', 'The reason')
      @handler.add(ex)

      entries = parse_error_entries(@handler.err_file)
      entry = entries[0]
      example = golden_schema["cheffs_not_found_error"]["example"]

      expect(entry["exception"]).to eq(example["exception"])
      expect(entry["entry"]).to eq(example["entry"])
      expect(entry["reason"]).to eq(example["reason"])
      expect(entry["transient"]).to eq(example["transient"])
    end
  end

  context "ChefFS OperationFailedError output schema" do
    it "matches the golden schema for cheffs_operation_failed_error" do
      ex = Chef::ChefFS::FileSystem::OperationFailedError.new(:read, '/boop', 'The exception', 'The reason')
      @handler.add(ex)

      entries = parse_error_entries(@handler.err_file)
      expect(entries.length).to eq(1)
      validate_entry_against_schema(entries[0], "cheffs_operation_failed_error")
    end

    it "includes the expected example values" do
      ex = Chef::ChefFS::FileSystem::OperationFailedError.new(:read, '/boop', 'The exception', 'The reason')
      @handler.add(ex)

      entries = parse_error_entries(@handler.err_file)
      entry = entries[0]
      example = golden_schema["cheffs_operation_failed_error"]["example"]

      expect(entry["exception"]).to eq(example["exception"])
      expect(entry["entry"]).to eq(example["entry"])
      expect(entry["operation"]).to eq(example["operation"])
      expect(entry["transient"]).to eq(example["transient"])
    end
  end

  context "connection error output schema" do
    it "matches the golden schema for connection_error" do
      ex = Errno::ECONNRESET.new("Connection reset by peer")
      @handler.add(ex)

      entries = parse_error_entries(@handler.err_file)
      expect(entries.length).to eq(1)
      validate_entry_against_schema(entries[0], "connection_error")
    end

    it "does not include http_code for non-HTTP errors" do
      ex = Errno::ECONNRESET.new("Connection reset by peer")
      @handler.add(ex)

      entries = parse_error_entries(@handler.err_file)
      expect(entries[0]).not_to have_key("http_code")
      expect(entries[0]).not_to have_key("entry")
      expect(entries[0]).not_to have_key("operation")
    end
  end

  context "schema file integrity" do
    it "golden schema file exists and is valid JSON" do
      expect(File.exist?(GOLDEN_PATH)).to be true
      expect { JSON.parse(File.read(GOLDEN_PATH)) }.not_to raise_error
    end

    it "golden schema covers all error types" do
      expect(golden_schema.keys).to contain_exactly(
        "http_error",
        "cheffs_not_found_error",
        "cheffs_operation_failed_error",
        "connection_error"
      )
    end
  end
end
