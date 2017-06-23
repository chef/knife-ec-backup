require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "spec_helper"))
require 'chef/knife/ec_backup'
require 'fakefs/spec_helpers'

describe Chef::Knife::EcBackup do
  let(:dest_dir) { Dir.mktmpdir }
  USER_RESPONSE = {
    "foo" => "organizations/bar/users/foo",
    "bar" => "organizations/bar/users/bar"
  }

  ORG_RESPONSE = {
    "foo" => "organizations/bar",
    "bar" => "organizations/foo"
  }

  def org_response(name, unassigned=false)
    r = { "name" => name,
      "full_name" => name,
      "org_type" => "Business",
      "clientname" => "#{name}-validator",
      "guid" => "994191e436b740c9b229e64dc9a57517",
      "chargify_subscription_id" => nil,
      "chargify_customer_id" => nil,
      "billing_plan" => "platform-free"
    }
    r['assigned_at'] = "2014/11/21 11:23:57 +0000" unless unassigned
    r
  end

  before(:each) do
    Chef::Knife::EcBackup.load_deps
    @knife = Chef::Knife::EcBackup.new
    @rest = double('Chef::ServerAPI')
    allow(@knife).to receive(:rest).and_return(@rest)
    allow(@knife).to receive(:user_acl_rest).and_return(@rest)
    allow_any_instance_of(Chef::Knife::EcBase).to receive(:dest_dir).and_return(dest_dir)
  end

  describe "#for_each_user" do
    it "iterates over remote users" do
      allow(@rest).to receive(:get).with("/users").and_return(USER_RESPONSE)
      expect{ |b| @knife.for_each_user(&b) }.to yield_successive_args(["foo", USER_RESPONSE["foo"]], ["bar", USER_RESPONSE["bar"]])
    end

    context "when there are HTTP failures" do
      let(:ec_error_handler) { double("Chef::Knife::EcErrorHandler") }

      it "adds exceptions to error handler" do
        exception = net_exception(500)
        allow(Chef::Knife::EcErrorHandler).to receive(:new).and_return(ec_error_handler)
        allow(@rest).to receive(:get).with("/users").and_raise(exception)
        expect(ec_error_handler).to receive(:add).at_least(1).with(exception)
        @knife.for_each_user
      end
    end
  end

  describe "#for_each_organization" do
    before(:each) do
      allow(@rest).to receive(:get).with("/organizations").and_return(ORG_RESPONSE)
    end

    it "iterates over remote organizations" do
      allow(@rest).to receive(:get).with("organizations/bar").and_return(org_response("bar"))
      allow(@rest).to receive(:get).with("organizations/foo").and_return(org_response("foo"))
      expect{ |b| @knife.for_each_organization(&b) }.to yield_successive_args(org_response("bar"), org_response("foo"))
    end

    it "skips unassigned (precreated) organizations on Chef Server 11" do
      server = double('Chef::Server')
      allow(Chef::Server).to receive(:new).and_return(server)
      allow(server).to receive(:version).and_return(Gem::Version.new("11.12.3"))
      allow(@rest).to receive(:get).with("organizations/bar").and_return(org_response("bar"))
      allow(@rest).to receive(:get).with("organizations/foo").and_return(org_response("foo", true))
      expect{ |b| @knife.for_each_organization(&b) }.to yield_successive_args(org_response("bar"))
    end

    it "includes *all* organizations on Chef Server 12" do
      server = double('Chef::Server')
      allow(Chef::Server).to receive(:new).and_return(server)
      allow(server).to receive(:version).and_return(Gem::Version.new("12.0.0"))
      allow(@rest).to receive(:get).with("organizations/bar").and_return(org_response("bar"))
      allow(@rest).to receive(:get).with("organizations/foo").and_return(org_response("foo", true))
      expect{ |b| @knife.for_each_organization(&b) }.to yield_successive_args(org_response("bar"),
                                                                              org_response("foo", true))
    end

    context "when there are HTTP failures" do
      let(:ec_error_handler) { double("Chef::Knife::EcErrorHandler") }

      before(:each) do
        server = double('Chef::Server')
        allow(Chef::Server).to receive(:new).and_return(server)
        allow(Chef::Knife::EcErrorHandler).to receive(:new).and_return(ec_error_handler)
        allow(server).to receive(:version).and_return(Gem::Version.new("12.0.0"))
      end

      it "adds exception and continues with the rest of the orgs" do
        exception = net_exception(404)
        allow(@rest).to receive(:get).with("organizations/foo").and_return(org_response("foo"))
        allow(@rest).to receive(:get).with("organizations/bar").and_raise(exception)
        expect(ec_error_handler).to receive(:add).at_least(1).with(exception)
        expect{ |b| @knife.for_each_organization(&b) }.to yield_successive_args(org_response("foo"))
      end

      it "adds exceptions to error handler" do
        allow(@rest).to receive(:get).with("organizations/foo").and_raise(net_exception(500))
        allow(@rest).to receive(:get).with("organizations/bar").and_raise(net_exception(404))
        expect(ec_error_handler).to receive(:add).at_least(2)
        @knife.for_each_organization
      end
    end
  end

  describe "#download_user" do
    include FakeFS::SpecHelpers
    let (:username) { "foo" }
    let (:url) { "users/foo" }
    before(:each) { FileUtils.mkdir_p(File.join(dest_dir, "users")) }

    it "downloads a named user from the api" do
      expect(@rest).to receive(:get).with(url)
      @knife.download_user(username, url)
    end

    it "writes it to a json file in the destination directory" do
      user_response = {"username" => "foo"}
      allow(@rest).to receive(:get).with(url).and_return(user_response)
      @knife.download_user(username, url)
      expect(JSON.parse(File.read("#{dest_dir}/users/foo.json"))).to eq(user_response)
    end
  end

  describe "#download_user_acl" do
    include FakeFS::SpecHelpers
    let (:username) {"foo"}
    before(:each) { FileUtils.mkdir_p(File.join(dest_dir, "user_acls")) }

    it "downloads a user acl from the API" do
      expect(@rest).to receive(:get).with("users/#{username}/_acl")
      @knife.download_user_acl(username)
    end

    it "writes it to a json file in the destination directory" do
      user_acl_response = {"create" => {}}
      allow(@rest).to receive(:get).with("users/#{username}/_acl").and_return(user_acl_response)
      @knife.download_user_acl(username)
      expect(JSON.parse(File.read("#{dest_dir}/user_acls/foo.json"))).to eq(user_acl_response)
    end

    context "when there are HTTP failures" do
      let(:ec_error_handler) { double("Chef::Knife::EcErrorHandler") }

      it "adds exceptions to error handler" do
        exception = net_exception(500)
        allow(Chef::Knife::EcErrorHandler).to receive(:new).and_return(ec_error_handler)
        allow(@rest).to receive(:get).with("users/#{username}/_acl").and_raise(exception)
        expect(ec_error_handler).to receive(:add).at_least(1).with(exception)
        @knife.download_user_acl(username)
      end
    end
  end

  describe "#write_org_object_to_disk" do
    include FakeFS::SpecHelpers
    it "writes the given object to disk" do
      org_object = { "name" => "bob" }
      @knife.write_org_object_to_disk(org_object)
      expect(JSON.parse(File.read("/organizations/bob/org.json"))).to eq(org_object)
    end
  end

  describe "#download_org_members" do
    include FakeFS::SpecHelpers
    let (:users) {
      [  {
           "user" => { "username" => "john" }
         },
         {
           "user" => { "username" => "mary" }
         }
      ]
    }

    it "downloads org members for a given org" do
      expect(@rest).to receive(:get).with("/organizations/bob/users").and_return(users)
      @knife.download_org_members("bob")
    end

    it "writes the org members to a JSON file" do
      expect(@rest).to receive(:get).with("/organizations/bob/users").and_return(users)
      @knife.download_org_members("bob")
      expect(JSON.parse(File.read("#{dest_dir}/organizations/bob/members.json"))).to eq(users)
    end

    context "when there are HTTP failures" do
      let(:ec_error_handler) { double("Chef::Knife::EcErrorHandler") }

      it "adds exceptions to error handler" do
        exception = net_exception(500)
        allow(Chef::Knife::EcErrorHandler).to receive(:new).and_return(ec_error_handler)
        allow(@rest).to receive(:get).with("/organizations/bob/users").and_raise(exception)
        expect(ec_error_handler).to receive(:add).at_least(1).with(exception)
        @knife.download_org_members("bob")
      end
    end

  end

  describe "#download_org_inivitations" do
    include FakeFS::SpecHelpers
    let(:invites) { {"a json" => "maybe"} }
    it "downloads invitations for a given org" do
      expect(@rest).to receive(:get).with("/organizations/bob/association_requests").and_return(invites)
      @knife.download_org_invitations("bob")
    end

    it "writes the invitations to a JSON file" do
      expect(@rest).to receive(:get).with("/organizations/bob/association_requests").and_return(invites)
      @knife.download_org_invitations("bob")
      expect(JSON.parse(File.read("/organizations/bob/invitations.json"))).to eq(invites)
    end
  end
end
