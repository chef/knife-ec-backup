require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "spec_helper"))
require 'chef/knife/ec_base'
require 'chef/knife'
require 'chef/config'
require 'stringio'

class Tester < Chef::Knife
  include Chef::Knife::EcBase
end

describe Chef::Knife::EcBase do
  let(:o) { Tester.new }
  before(:each) do
    @rest = double('rest')
    @stderr = StringIO.new
    allow(o.ui).to receive(:stderr).and_return(@stderr)
    allow(Chef::REST).to receive(:new).and_return(@rest)
  end

  context "org_admin" do
    it "selects an admin from an org" do
      allow(@rest).to receive(:get_rest).with("groups/admins").and_return({"users" => ["bob"]})
      allow(@rest).to receive(:get_rest).with("users").and_return([{"user" => { "username" => "bob"}}])
      expect(o.org_admin).to eq("bob")
    end

    it "refuses to return pivotal" do
      allow(@rest).to receive(:get_rest).with("groups/admins").and_return({"users" => ["pivotal"]})
      allow(@rest).to receive(:get_rest).with("users").and_return([{"user" => { "username" => "pivotal"}}])
      expect{o.org_admin}.to raise_error(Chef::Knife::EcBase::NoAdminFound)
    end

    it "refuses to return users not in the org" do
      allow(@rest).to receive(:get_rest).with("groups/admins").and_return({"users" => ["bob"]})
      allow(@rest).to receive(:get_rest).with("users").and_return([{"user" => { "username" => "sally"}}])
      expect{o.org_admin}.to raise_error(Chef::Knife::EcBase::NoAdminFound)
    end
  end

  context "set_dest_dir_from_args!" do
    it "sets dest_dir from its arguments" do
      o.name_args = ["foo"]
      o.set_dest_dir_from_args!
      expect(o.dest_dir).to eq("foo")
    end

    it "exits with an error message if no argument is given" do
      expect {o.set_dest_dir_from_args!}.to raise_error(SystemExit)
    end
  end

  context "set_client_config!" do
    it "doesn't mutate config if node_name is pivotal" do
      Chef::Config.node_name = "pivotal"
      Chef::Config.client_key = "blargblarg"
      o.set_client_config!
      expect(Chef::Config.node_name).to eq("pivotal")
      expect(Chef::Config.client_key).to eq("blargblarg")
    end

    it "exits with an error if the pivotal key doesn't exist" do
      Chef::Config.node_name = "wombat"
      Chef::Config.client_key = "blargblarg"
      expect {o.set_client_config!}.to raise_error(SystemExit)
    end

    it "sets the client key and node name if they look incorrect" do
      Chef::Config.node_name = "wombat"
      Chef::Config.client_key = "blargblarg"
      allow(File).to receive(:exist?).and_return(true)
      o.set_client_config!
      expect(Chef::Config.node_name).to eq("pivotal")
      expect(Chef::Config.client_key).to eq("/etc/opscode/pivotal.pem")
    end
  end

  context "ensure_webui_key_exists!" do
    it "exits when the webui_key doesn't exist" do
      o.config[:webui_key] = "dne"
      expect{o.ensure_webui_key_exists!}.to raise_error(SystemExit)
    end
  end
end
