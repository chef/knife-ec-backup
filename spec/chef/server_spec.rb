require File.expand_path(File.join(File.dirname(__FILE__), "..", "spec_helper"))
require 'chef/server'
require 'chef/server_api'
require 'stringio'

describe Chef::Server do
  before(:each) do
    @rest = double('rest')
    allow(Chef::ServerAPI).to receive(:new).and_return(@rest)
  end

  it "infers root url from a Chef Server url" do
    s = Chef::Server.from_chef_server_url("http://api.example.com/organizations/foobar")
    expect(s.root_url).to eq("http://api.example.com")
  end

  it "determines the running habitat service dockerized pkg version" do
    s = Chef::Server.new('http://api.example.com')
    allow(@rest).to receive(:get).with("version").and_return(StringIO.new("Package: chef-server/chef-server-nginx/12.17.42/20180413212943\nother stuff\nother stuff"))
    expect(s.version.to_s).to eq('12.17.42')
  end

  it "determines the running Automate CS API habitat service pkg version" do
    s = Chef::Server.new('http://api.example.com')
    allow(@rest).to receive(:get).with("version").and_return(StringIO.new("Package: chef/automate-cs-nginx/12.19.31/20190529200833\nHabitat: 0.69.0/20181127183841\nMember: f73decd1025f4a5aa728b4429c297ef1 / ip-10-1-1-200.us-west-1.compute.internal"))
    expect(s.version.to_s).to eq('12.19.31')
  end

  it "determines the running omnibus server version" do
    s = Chef::Server.new('http://api.example.com')
    allow(@rest).to receive(:get).with("version").and_return(StringIO.new("Chef Server 1.8.1\nother stuff\nother stuff"))
    expect(s.version.to_s).to eq('1.8.1')
  end

  it "ignores git tags when determining the version" do
    s = Chef::Server.new("http://api.example.com")
    allow(@rest).to receive(:get).with("version").and_return(StringIO.new("Chef Server 1.8.1+20141024080718.git.16.08098a5\nother stuff\nother stuff"))
    expect(s.version.to_s).to eq("1.8.1")
  end

  it "knows whether the server supports user ACLs via nginx" do
    s1 = Chef::Server.new("http://api.example.com")
    allow(@rest).to receive(:get).with("version").and_return(StringIO.new("Chef Server 11.0.0\nother stuff\nother stuff"))
    expect(s1.supports_user_acls?).to eq(false)
    s2 = Chef::Server.new("http://api.example.com")
    allow(@rest).to receive(:get).with("version").and_return(StringIO.new("Chef Server 11.0.2\nother stuff\nother stuff"))
    expect(s2.supports_user_acls?).to eq(true)
  end

  it "knows when account is directly accessible" do
    s = Chef::Server.new("http://api.example.com")
    allow(@rest).to receive(:get).and_return("")
    expect(s.direct_account_access?).to eq(true)
  end

  it "knows when account is not directly accessible" do
    s = Chef::Server.new("http://api.example.com")
    allow(@rest).to receive(:get).and_raise(Errno::ECONNREFUSED)
    expect(s.direct_account_access?).to eq(false)
  end

  it "knows that public_key_read_access was implemented in 12.5.0" do
    before = Chef::Server.new("http://api.example.com")
    allow(@rest).to receive(:get).with("version").and_return(StringIO.new("Chef Server 12.4.1\nother stuff\nother stuff"))
    expect(before.supports_public_key_read_access?).to eq(false)
    after = Chef::Server.new("http://api.example.com")
    allow(@rest).to receive(:get).with("version").and_return(StringIO.new("Chef Server 12.6.0\nother stuff\nother stuff"))
    expect(after.supports_public_key_read_access?).to eq(true)
  end
end
