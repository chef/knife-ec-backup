require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "spec_helper"))
require 'chef/knife/ec_key_export'
require 'sequel'
require 'json' unless defined?(JSON)
require 'securerandom' unless defined?(SecureRandom)
require 'fakefs/spec_helpers'

def user_record(name)
  { "id" => SecureRandom.uuid,
    "authz_id" => SecureRandom.uuid,
    "username" => name,
    "email" => "#{name}@example.com",
    "pubkey_version" => 0,
    "public_key" => "BEGIN RSA PUBLIC KEY",
    "serialized_object" => "{ \"a string\" => \"of JSONNNN\"}",
    "last_updated_by" => "a time",
    "created_at" => "a time",
    "updated_at" => "a time",
    "external_authentication_uid" => nil,
    "recovery_authentication_enabled" => false,
    "admin" => false,
    "hashed_password" => "alkdsj5834751934",
    "salt" => "01943891jgfkjf",
    "hash_type" => "not good 1.0" }
end

def key_record(name, type, key_name)
  {
    "id" => SecureRandom.uuid,
    "org_id" => SecureRandom.uuid,
    "name" => name,
    "authz_id" => SecureRandom.uuid,
    "type" => type.to_s,
    "key_name" => key_name,
    "public_key" => "BEGIN RSA PUBLIC KEY",
    "key_version" => 0,
    "expires_at" => "a time"
  }
end

describe Chef::Knife::EcKeyExport do
  include FakeFS::SpecHelpers
  let(:users_table) do
    [ user_record("jane"),
      user_record("bob") ]
  end

  let(:keys_by_name_table) do
    [ key_record("bob", :user, "default"),
      key_record("jane", :user, "default"),
      key_record("rabbit", :client, "default") ]
  end

  let(:db) do
    # This seem to be the way to vary fetched data on output
    # See https://groups.google.com/forum/#!topic/sequel-talk/NZuxcoXN30M
    output = Proc.new do |query|
      case query
       when /SELECT.*users/ then users_table
       when /SELECT.*keys_by_name/ then keys_by_name_table
       end
    end
    d = Sequel.mock(:fetch => output)
    allow(Sequel).to receive(:connect).and_return(d)
    d
  end

  let(:knife) do
    Chef::Knife::EcKeyExport.deps
    k = Chef::Knife::EcKeyExport.new
    k.config[:sql_user] = "opscode_chef"
    k.config[:sql_password] = "apassword"
    k.config[:sql_host] = "localhost"
    k.config[:sql_port] = 5432
    k
  end

  it "writes the users table to json" do
    db; knife.run
    expect(JSON.parse(File.read("key_dump.json"))).to eq(users_table)
  end

  it "writes the keys_by_name table to json" do
    db; knife.run
    expect(JSON.parse(File.read("key_table_dump.json"))).to eq(keys_by_name_table)
  end

  it "does not write the users table if :skip_users_table is set" do
    knife.config[:skip_users_table] = true
    db; knife.run
    expect(File.exist?("key_dump.json")).to eq(false)
  end

  it "does not write the keys_by_name table if :skip_keys_table is set" do
    knife.config[:skip_keys_table] = true
    db; knife.run
    expect(File.exist?("key_table_dump.json")).to eq(false)
  end

  it "writes the tables to the specified files when given arguments" do
    knife.name_args = ["user_table.json", "key_table.json"]
    db; knife.run
    expect(JSON.parse(File.read("user_table.json"))).to eq(users_table)
    expect(JSON.parse(File.read("key_table.json"))).to eq(keys_by_name_table)
  end
end
