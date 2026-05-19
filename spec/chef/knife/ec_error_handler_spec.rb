require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "spec_helper"))
require 'chef/knife/ec_error_handler'
require 'chef/knife/ec_backup'
require 'chef/knife/ec_restore'
require 'chef/chef_fs/config'
require 'chef/chef_fs/file_system'
require 'fakefs/spec_helpers'

def net_exception(code)
  s = double("status", :code => code.to_s)
  Net::HTTPServerException.new("I'm not real!", s)
end

def cheffs_filesystem_exception(type)
  case type
  when 'NotFoundError'
    Chef::ChefFS::FileSystem::NotFoundError.new('/boop', 'The exception', 'The reason')
  when 'OperationFailedError'
    Chef::ChefFS::FileSystem::OperationFailedError.new(:read, '/boop', 'The exception', 'The reason')
  else
    raise RuntimeError, 'invalid type passed'
  end
end

describe Chef::Knife::EcErrorHandler do
  let(:dest_dir) { Dir.mktmpdir }
  let(:err_dir)  { File.join(dest_dir, "errors") }

  before(:each) do
    allow(Time).to receive(:now).and_return(Time.new(1988, 04, 17, 0, 0, 0, "+00:00")) #=> 1988-04-17 00:00:00 +0000
    @knife_ec_error_handler = described_class.new(dest_dir, Class, suppress_exit: true)
  end

  describe "#initialize" do
    it "creates an error directory" do
      expect(FileUtils).to receive(:mkdir_p).with("#{dest_dir}/errors")
      described_class.new(dest_dir, Class, suppress_exit: true)
    end

    it "sets up an err_file depending of the class that comes from" do
      ec_backup = described_class.new(dest_dir, Chef::Knife::EcBackup, suppress_exit: true)
      expect(ec_backup.err_file).to match File.join(err_dir, "backup-1988-04-17T00:00:00+00:00.json")
      ec_restore = described_class.new(dest_dir, Chef::Knife::EcRestore, suppress_exit: true)
      expect(ec_restore.err_file).to match File.join(err_dir, "restore-1988-04-17T00:00:00+00:00.json")
      ec_other = described_class.new(dest_dir, Class, suppress_exit: true)
      expect(ec_other.err_file).to match File.join(err_dir, "other-1988-04-17T00:00:00+00:00.json")
    end

    it "starts with zero error_count" do
      expect(@knife_ec_error_handler.error_count).to eq(0)
    end

    it "starts with has_errors? as false" do
      expect(@knife_ec_error_handler.has_errors?).to be false
    end
  end

  describe "#has_errors?" do
    it "returns true after an error is added" do
      @knife_ec_error_handler.add(net_exception(500))
      expect(@knife_ec_error_handler.has_errors?).to be true
    end

    it "increments error_count for each error added" do
      @knife_ec_error_handler.add(net_exception(500))
      @knife_ec_error_handler.add(net_exception(404))
      expect(@knife_ec_error_handler.error_count).to eq(2)
    end
  end

  describe "#transient_error?" do
    it "identifies 500 errors as transient" do
      ex = net_exception(500)
      expect(@knife_ec_error_handler.transient_error?(ex)).to be true
    end

    it "identifies 503 errors as transient" do
      ex = net_exception(503)
      expect(@knife_ec_error_handler.transient_error?(ex)).to be true
    end

    it "identifies 404 errors as non-transient" do
      ex = net_exception(404)
      expect(@knife_ec_error_handler.transient_error?(ex)).to be false
    end

    it "identifies 409 errors as non-transient" do
      ex = net_exception(409)
      expect(@knife_ec_error_handler.transient_error?(ex)).to be false
    end

    it "identifies Errno::ECONNRESET as transient" do
      ex = Errno::ECONNRESET.new("Connection reset by peer")
      expect(@knife_ec_error_handler.transient_error?(ex)).to be true
    end

    it "identifies Errno::ECONNREFUSED as transient" do
      ex = Errno::ECONNREFUSED.new("Connection refused")
      expect(@knife_ec_error_handler.transient_error?(ex)).to be true
    end

    it "identifies Errno::ETIMEDOUT as transient" do
      ex = Errno::ETIMEDOUT.new("Connection timed out")
      expect(@knife_ec_error_handler.transient_error?(ex)).to be true
    end

    it "identifies ChefFS NotFoundError as non-transient" do
      ex = cheffs_filesystem_exception('NotFoundError')
      expect(@knife_ec_error_handler.transient_error?(ex)).to be false
    end
  end

  it "#display" do
    @knife_ec_error_handler.add(net_exception(123))
    expect { @knife_ec_error_handler.display }.to output(/Error Summary Report/).to_stdout
  end

  describe "#add" do
    it "writes errors to the error file" do
      err_file = @knife_ec_error_handler.err_file
      @knife_ec_error_handler.add(net_exception(500))
      @knife_ec_error_handler.add(net_exception(409))
      @knife_ec_error_handler.add(net_exception(404))
      @knife_ec_error_handler.add(net_exception(123))
      @knife_ec_error_handler.add(cheffs_filesystem_exception('NotFoundError'))
      @knife_ec_error_handler.add(cheffs_filesystem_exception('OperationFailedError'))

      content = File.read(err_file)
      expect(content).to include('"exception": "Net::HTTPServerException"')
      expect(content).to include('"exception": "Chef::ChefFS::FileSystem::NotFoundError"')
      expect(content).to include('"exception": "Chef::ChefFS::FileSystem::OperationFailedError"')
      expect(content).to include('"entry": "/boop"')
      expect(content).to include('"reason": "The reason"')
      expect(content).to include('"operation": "read"')
    end

    it "marks transient errors correctly" do
      err_file = @knife_ec_error_handler.err_file
      @knife_ec_error_handler.add(net_exception(500))
      content = File.read(err_file)
      expect(content).to include('"transient": true')
    end

    it "marks non-transient errors correctly" do
      err_file = @knife_ec_error_handler.err_file
      @knife_ec_error_handler.add(net_exception(404))
      content = File.read(err_file)
      expect(content).to include('"transient": false')
    end

    it "includes http_code for HTTP exceptions" do
      err_file = @knife_ec_error_handler.err_file
      @knife_ec_error_handler.add(net_exception(500))
      content = File.read(err_file)
      expect(content).to include('"http_code": "500"')
    end

    it "handles connection reset errors gracefully" do
      err_file = @knife_ec_error_handler.err_file
      ex = Errno::ECONNRESET.new("Connection reset by peer")
      @knife_ec_error_handler.add(ex)
      content = File.read(err_file)
      expect(content).to include('Connection reset by peer')
      expect(content).to include('"transient": true')
    end

    it "calls to_json_pretty for each error" do
      expect(Chef::JSONCompat).to receive(:to_json_pretty)
        .at_least(4)
        .and_call_original
      @knife_ec_error_handler.add(net_exception(500))
      @knife_ec_error_handler.add(net_exception(409))
      @knife_ec_error_handler.add(net_exception(404))
      @knife_ec_error_handler.add(net_exception(123))
    end

    it "locks the file for each write" do
      err_file = @knife_ec_error_handler.err_file
      expect(File).to receive(:open)
        .at_least(2)
        .with(err_file, "a")
        .and_call_original
      @knife_ec_error_handler.add(net_exception(500))
      @knife_ec_error_handler.add(net_exception(404))
    end
  end
end
