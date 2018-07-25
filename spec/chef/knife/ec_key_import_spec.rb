require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "spec_helper"))
require 'chef/knife/ec_key_import'
require 'sequel'
require 'json'
require 'securerandom'
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

describe Chef::Knife::EcKeyImport do
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
       when /SELECT.*FROM \"users\" WHERE \(\"username\" = '(?<username>.*)'/ then users_table.select {|x| x['username'] == $LAST_MATCH_INFO['username']}
       when /SELECT.*users/ then users_table
       #when /SELECT.*users\ WHERE \(username = '(?<username>.*)')/ then users_table.select {|x| x['username'] == $LAST_MATCH_INFO['username'] }
       when /SELECT.*keys_by_name/ then keys_by_name_table
       end
    end
    d = Sequel.mock(:fetch => output)
    allow(Sequel).to receive(:connect).and_return(d)
    d
  end

  let(:knife) do
    Chef::Knife::EcKeyImport.deps
    k = Chef::Knife::EcKeyImport.new
    k.config[:sql_user] = "opscode_chef"
    k.config[:sql_password] = "apassword"
    k.config[:sql_host] = "localhost"
    k.config[:sql_port] = 5432
    k
  end

  before do
    allow(File).to receive(:read).with('/tmp/key_dump.json').and_return(users_table.to_json)
    ENV["HOME"] = "/tmp"
  end

  it "imports user data except the id" do
    db; knife.import_user_data('/tmp/key_dump.json')
    expect(Chef::Knife::EcKeyImport).to receive('import_user_data').with('/tmp/key_dump.json').and_return("2")
    #expect(Chef::Knife::EcKeyImport).to receive('import_user_data').and_return("2")
    #expect(Sequel::Postgres::Dataset).to receive(:update).and_return(1)
    #expect(File.read("/tmp/key_dump.json")).to eq(users_table.to_json)
  end
end
