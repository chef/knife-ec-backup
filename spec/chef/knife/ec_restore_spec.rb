require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "spec_helper"))
require 'chef/knife/ec_restore'
require 'fakefs/spec_helpers'
require_relative './ec_error_handler_spec'
require "chef/chef_fs/file_system/repository/chef_repository_file_system_root_dir"

def make_user(username)
  FileUtils.mkdir_p("/users")
  File.write("/users/#{username}.json", "{\"username\": \"#{username}\"}")
end

def make_org(orgname)
  FileUtils.mkdir_p("/organizations/#{orgname}")
  File.write("/organizations/#{orgname}/org.json", "{\"name\": \"#{orgname}\"}")
  File.write("/organizations/#{orgname}/invitations.json", "[{\"username\": \"bob\"}, {\"username\": \"jane\"}]")
end

def net_exception(code)
  s = double("status", :code => code.to_s)
  Net::HTTPServerException.new("I'm not real!", s)
end

describe Chef::Knife::EcRestore do

  before(:each) do
    Chef::Knife::EcRestore.load_deps
    @knife = Chef::Knife::EcRestore.new
    @rest = double('Chef::ServerAPI')
    allow(@knife).to receive(:rest).and_return(@rest)
    allow(@knife).to receive(:user_acl_rest).and_return(@rest)
  end

  describe "#create_organization" do
    include FakeFS::SpecHelpers
    it "posts a given org to the API from data on disk" do
      make_org "foo"
      org = JSON.parse(File.read("/organizations/foo/org.json"))
      expect(@rest).to receive(:post).with("organizations", org)
      @knife.create_organization("foo")
    end

    it "updates a given org if it already exists" do
      make_org "foo"
      org = JSON.parse(File.read("/organizations/foo/org.json"))
      allow(@rest).to receive(:post).with("organizations", org).and_raise(net_exception(409))
      expect(@rest).to receive(:put).with("organizations/foo", org)
      @knife.create_organization("foo")
    end
  end

  describe "#restore_open_invitations" do
    include FakeFS::SpecHelpers

    it "reads the invitations from disk and posts them to the API" do
      make_org "foo"
      expect(@rest).to receive(:post).with("organizations/foo/association_requests", {"user" => "bob"})
      expect(@rest).to receive(:post).with("organizations/foo/association_requests", {"user" => "jane"})
      @knife.restore_open_invitations("foo")
    end

    it "does NOT fail if an inivitation already exists" do
      make_org "foo"
      allow(@rest).to receive(:post).with("organizations/foo/association_requests", {"user" => "bob"}).and_return(net_exception(409))
      allow(@rest).to receive(:post).with("organizations/foo/association_requests", {"user" => "jane"}).and_return(net_exception(409))
      expect {@knife.restore_open_invitations("foo")}.to_not raise_error
    end
  end

  describe "#for_each_user" do
    include FakeFS::SpecHelpers
    it "iterates over all users with files on disk" do
      make_user("bob")
      make_user("jane")
      expect{|b| @knife.for_each_user &b }.to yield_successive_args("bob", "jane")
    end

    it "skips pivotal when config[:overwrite_pivotal] is false" do
      @knife.config[:overwrite_pivotal] = false
      make_user("bob")
      make_user("pivotal")
      make_user("jane")
      expect{|b| @knife.for_each_user &b }.to yield_successive_args("bob", "jane")
    end

    it "does not skip pivotal when config[:overwrite_pivotal] is true" do
      @knife.config[:overwrite_pivotal] = true
      make_user("bob")
      make_user("pivotal")
      make_user("jane")
      expect{|b| @knife.for_each_user &b }.to yield_successive_args("bob", "pivotal", "jane")
    end

    it "does not return non-json files in the directory" do
      make_user("bob")
      make_user("jane")
      File.write("/users/nonono", "")
      expect{|b| @knife.for_each_user &b }.to yield_successive_args("bob", "jane")
    end
  end

  describe "#for_each_organization" do
    include FakeFS::SpecHelpers
    it "iterates over all organizations with a folder on disk" do
      make_org "acme"
      make_org "wombats"
      expect{|b| @knife.for_each_organization &b }.to yield_successive_args("acme", "wombats")
    end

    it "only return config[:org] when the option is specified" do
      make_org "acme"
      make_org "wombats"
      @knife.config[:org] = "wombats"
      expect{|b| @knife.for_each_organization &b }.to yield_with_args("wombats")
    end
  end

  describe "#restore_users" do
    include FakeFS::SpecHelpers

    it "reads the user from disk and posts it to the API" do
      make_user "jane"
      expect(@rest).to receive(:post).with("users", anything)
      @knife.restore_users
    end

    it "sets a random password for users" do
      make_user "jane"
      # FIX ME: How can we test this better?
      expect(@rest).to receive(:post).with("users", {"username" => "jane", "password" => anything})
      @knife.restore_users
    end

    it "updates the user if it already exists" do
      make_user "jane"
      allow(@rest).to receive(:post).with("users", anything).and_raise(net_exception(409))
      expect(@rest).to receive(:put).with("users/jane", {"username" => "jane"})
      @knife.restore_users
    end

    context "when there are HTTP failures with different code than 409" do
      let(:ec_error_handler) { double("Chef::Knife::EcErrorHandler") }

      it "adds exceptions to error handler" do
        make_user "jane"
        exception = net_exception(500)
        allow(Chef::Knife::EcErrorHandler).to receive(:new).and_return(ec_error_handler)
        allow(@rest).to receive(:post).with("users", anything).and_raise(exception)
        expect(ec_error_handler).to receive(:add).at_least(1).with(exception)
        @knife.restore_users
      end
    end
  end

  describe "#restore_group" do
    context "when group is not present in backup" do
      let(:chef_fs_config) { Chef::ChefFS::Config.new }
      let(:group_name) { "bad_group" }

      it "does not raise error" do
        expect { @knife.restore_group(chef_fs_config, group_name) }.not_to raise_error
      end
    end
  end

  describe "#chef_fs_copy_pattern" do
    context "when there are Filesystem errors" do
      let(:ec_error_handler) { double("Chef::Knife::EcErrorHandler") }
      let(:cheffs_config) { double("Chef::ChefFS::Config") }
      let(:cheffs_files) { double("Chef::ChefFS::FileSystem") }
      let(:cheffs_local_fs) { double('Chef::ChefFS::FileSystem::Repository::ChefRepositoryFileSystemRootDir') }
      let(:chef_fs) { double('applefs') }

      it "adds exceptions to error handler" do
        exception = cheffs_filesystem_exception('NotFoundError')
        allow(Chef::Knife::EcErrorHandler).to receive(:new).and_return(ec_error_handler)
        allow(Chef::ChefFS::Config).to receive(:new).and_return(cheffs_config)
        allow(Chef::ChefFS::FileSystem::Repository::ChefRepositoryFileSystemRootDir).to receive(:new).and_return(cheffs_local_fs)
        allow(Chef::ChefFS::FileSystem).to receive(:copy_to).with(any_args).and_raise(exception)
        allow(cheffs_config).to receive(:chef_fs).and_return(chef_fs)
        allow(cheffs_config).to receive(:local_fs).and_return(cheffs_local_fs)
        expect(ec_error_handler).to receive(:add).at_least(1).with(exception)
        @knife.chef_fs_copy_pattern('bob', cheffs_config)
      end
    end
  end
end
