require File.expand_path(File.join(File.dirname(__FILE__), "..", "spec_helper"))
require 'chef/server'
require 'chef/rest'
require 'stringio'

describe Chef::Server do

  it "infers root url from a Chef Server url" do
    s = Chef::Server.from_chef_server_url("http://api.example.com/organizations/foobar")
    expect(s.root_url).to eq("http://api.example.com")
  end

  it "determines the server version" do
    s = Chef::Server.new("http://api.example.com")
    allow(s).to receive(:open).and_return(StringIO.new("Chef Server 1.8.1\nother stuff\nother stuff"))
    expect(s.version.to_s).to eq("1.8.1")
  end

  it "knows whether the server supports user ACLs via ngingx" do
    s1 = Chef::Server.new("http://api.example.com")
    s2 = Chef::Server.new("http://api.example.com")
    allow(s1).to receive(:open).and_return(StringIO.new("Chef Server 11.0.0\nother stuff\nother stuff"))
    allow(s2).to receive(:open).and_return(StringIO.new("Chef Server 11.0.2\nother stuff\nother stuff"))

    expect(s1.supports_user_acls?).to eq(false)
    expect(s2.supports_user_acls?).to eq(true)
  end

  it "knows when account is directly accessible" do
    s = Chef::Server.new("http://api.example.com")
    rest_class = double('rest_class')
    rest = double('rest')
    stub_const("Chef::REST", rest_class)
    allow(rest_class).to receive(:new).and_return(rest)
    allow(rest).to receive(:get).and_return("")
    expect(s.direct_account_access?).to eq(true)
  end

  it "knows when account is not directly accessible" do
    s = Chef::Server.new("http://api.example.com")
    rest_class = double('rest_class')
    rest = double('rest')
    stub_const("Chef::REST", rest_class)
    allow(rest_class).to receive(:new).and_return(rest)
    allow(rest).to receive(:get).and_raise(Errno::ECONNREFUSED)
    expect(s.direct_account_access?).to eq(false)
  end
end
