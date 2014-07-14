require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "spec_helper"))
require 'chef/knife/ec_base'

class Tester
  def self.option(*args)
  end
  include Chef::Knife::EcBase
end

describe Chef::Knife::EcBase do
  let(:o) { Tester.new }
  before(:each) do
    rest_class = double('rest_class')
    @rest = double('rest')
    stub_const("Chef::REST", rest_class)
    allow(rest_class).to receive(:new).and_return(@rest)
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
end
