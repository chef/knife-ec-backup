require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "spec_helper"))
require 'chef/knife/ec_restore'
require 'fakefs/spec_helpers'
require_relative './ec_error_handler_spec'
require "chef/chef_fs/file_system/repository/chef_repository_file_system_root_dir"
require 'net/http'

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

    it "does NOT fail if an invitation already exists" do
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

  describe "#restore_cookbook_frozen_status" do
    include FakeFS::SpecHelpers

    let(:org_name) { "test_org" }
    let(:chef_fs_config) { double("Chef::ChefFS::Config") }
    let(:cookbooks_path) { "/organizations/#{org_name}/cookbooks" }

    before(:each) do
      allow(@knife).to receive(:dest_dir).and_return("")
      allow(@knife).to receive(:ui).and_return(double("ui", :msg => nil, :warn => nil))
    end

    context "when cookbooks directory does not exist" do
      it "returns early without processing" do
        expect(@knife).not_to receive(:freeze_cookbook)
        @knife.restore_cookbook_frozen_status(org_name, chef_fs_config)
      end
    end

    context "when cookbooks directory exists" do
      before(:each) do
        FileUtils.mkdir_p(cookbooks_path)
      end

      context "with no cookbook directories" do
        it "does not process any cookbooks" do
          expect(@knife).not_to receive(:freeze_cookbook)
          @knife.restore_cookbook_frozen_status(org_name, chef_fs_config)
        end
      end

      context "with cookbook directories" do
        let(:cookbook_name) { "apache2" }
        let(:version) { "1.2.3" }
        let(:cookbook_dir) { "#{cookbook_name}-#{version}" }
        let(:cookbook_path) { File.join(cookbooks_path, cookbook_dir) }
        let(:status_file) { File.join(cookbook_path, "status.json") }

        before(:each) do
          FileUtils.mkdir_p(cookbook_path)
        end

        context "when status.json does not exist" do
          it "skips the cookbook" do
            expect(@knife).not_to receive(:freeze_cookbook)
            @knife.restore_cookbook_frozen_status(org_name, chef_fs_config)
          end
        end

        context "when status.json exists" do
          context "and cookbook is frozen" do
            before(:each) do
              File.write(status_file, '{"frozen": true}')
            end

            it "calls freeze_cookbook with correct parameters" do
              expect(@knife).to receive(:freeze_cookbook).with(cookbook_name, version, org_name)
              @knife.restore_cookbook_frozen_status(org_name, chef_fs_config)
            end
          end

          context "and cookbook is not frozen" do
            before(:each) do
              File.write(status_file, '{"frozen": false}')
            end

            it "does not call freeze_cookbook" do
              expect(@knife).not_to receive(:freeze_cookbook)
              @knife.restore_cookbook_frozen_status(org_name, chef_fs_config)
            end
          end

          context "and status.json has invalid JSON" do
            before(:each) do
              File.write(status_file, 'invalid json')
            end

            it "warns about parse error and continues" do
              ui = double("ui")
              allow(@knife).to receive(:ui).and_return(ui)
              expect(ui).to receive(:msg).with("Restoring cookbook frozen status")
              expect(ui).to receive(:warn).with(/Failed to parse status\.json/)
              expect(@knife).not_to receive(:freeze_cookbook)
              @knife.restore_cookbook_frozen_status(org_name, chef_fs_config)
            end
          end

          context "with multiple cookbooks" do
            let(:frozen_cookbook) { "frozen-cookbook-2.0.0" }
            let(:unfrozen_cookbook) { "unfrozen-cookbook-1.5.0" }

            before(:each) do
              # Create frozen cookbook
              FileUtils.mkdir_p(File.join(cookbooks_path, frozen_cookbook))
              File.write(File.join(cookbooks_path, frozen_cookbook, "status.json"), '{"frozen": true}')

              # Create unfrozen cookbook
              FileUtils.mkdir_p(File.join(cookbooks_path, unfrozen_cookbook))
              File.write(File.join(cookbooks_path, unfrozen_cookbook, "status.json"), '{"frozen": false}')
            end

            it "only freezes the frozen cookbook" do
              expect(@knife).to receive(:freeze_cookbook).with("frozen-cookbook", "2.0.0", org_name).once
              expect(@knife).not_to receive(:freeze_cookbook).with("unfrozen-cookbook", "1.5.0", org_name)
              @knife.restore_cookbook_frozen_status(org_name, chef_fs_config)
            end
          end

          context "with cookbook name containing hyphens" do
            let(:cookbook_name) { "multi-word-cookbook" }
            let(:version) { "1.0.0" }

            before(:each) do
              cookbook_dir = "#{cookbook_name}-#{version}"
              cookbook_path = File.join(cookbooks_path, cookbook_dir)
              FileUtils.mkdir_p(cookbook_path)
              File.write(File.join(cookbook_path, "status.json"), '{"frozen": true}')
            end

            it "correctly parses cookbook name with hyphens" do
              expect(@knife).to receive(:freeze_cookbook).with(cookbook_name, version, org_name)
              @knife.restore_cookbook_frozen_status(org_name, chef_fs_config)
            end
          end
        end
      end
    end
  end

  describe "#freeze_cookbook" do
    let(:cookbook_name) { "apache2" }
    let(:version) { "1.2.3" }
    let(:org_name) { "test_org" }
    let(:manifest) { { "name" => cookbook_name, "version" => version, "frozen?" => false } }

    before(:each) do
      allow(@knife).to receive(:ui).and_return(double("ui", :msg => nil, :warn => nil))
    end

    context "when cookbook is not already frozen" do
      before(:each) do
        allow(@rest).to receive(:get).with("organizations/#{org_name}/cookbooks/#{cookbook_name}/#{version}").and_return(manifest)
      end

      it "freezes the cookbook successfully" do
        frozen_manifest = manifest.dup.tap { |h| h["frozen?"] = true }
        expect(@rest).to receive(:put).with("organizations/#{org_name}/cookbooks/#{cookbook_name}/#{version}?freeze=true", frozen_manifest)
        @knife.freeze_cookbook(cookbook_name, version, org_name)
      end
    end

    context "when cookbook is already frozen" do
      let(:frozen_manifest) { { "name" => cookbook_name, "version" => version, "frozen?" => true } }

      before(:each) do
        allow(@rest).to receive(:get).with("organizations/#{org_name}/cookbooks/#{cookbook_name}/#{version}").and_return(frozen_manifest)
      end

      it "skips freezing and warns" do
        ui = double("ui")
        allow(@knife).to receive(:ui).and_return(ui)
        expect(ui).to receive(:msg).with("Freezing cookbook #{cookbook_name} version #{version}")
        expect(ui).to receive(:warn).with(/already frozen/)
        expect(@rest).not_to receive(:put)
        @knife.freeze_cookbook(cookbook_name, version, org_name)
      end
    end

    context "when API call fails" do
      before(:each) do
        allow(@rest).to receive(:get).with("organizations/#{org_name}/cookbooks/#{cookbook_name}/#{version}").and_return(manifest)
        allow(@rest).to receive(:put).and_raise(net_exception(500))
        allow(@knife).to receive(:knife_ec_error_handler).and_return(double("error_handler", :add => nil))
      end

      it "handles the exception and adds to error handler" do
        ui = double("ui")
        error_handler = double("error_handler")
        allow(@knife).to receive(:ui).and_return(ui)
        allow(@knife).to receive(:knife_ec_error_handler).and_return(error_handler)

        expect(ui).to receive(:msg).with("Freezing cookbook #{cookbook_name} version #{version}")
        expect(ui).to receive(:warn).with(/Failed to freeze cookbook/)
        expect(error_handler).to receive(:add)

        @knife.freeze_cookbook(cookbook_name, version, org_name)
      end
    end
  end
end
