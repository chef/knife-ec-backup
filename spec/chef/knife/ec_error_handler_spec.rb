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
    Chef::ChefFS::FileSystem::NotFoundError.new(self, '/boop', 'I\'m not real!')
  when 'OperationFailedError'
    Chef::ChefFS::FileSystem::OperationFailedError.new(:read, self, '/boop', 'I\'m not real!')
  else
    raise RuntimeError, 'invalid type passed'
  end
end

describe Chef::Knife::EcErrorHandler do
  let(:dest_dir) { Dir.mktmpdir }
  let(:err_dir)  { File.join(dest_dir, "errors") }

  before(:each) do
    allow(Time).to receive(:now).and_return(Time.new(1988, 04, 17, 0, 0, 0, "+00:00")) #=> 1988-04-17 00:00:00 +0000
    @knife_ec_error_handler = described_class.new(dest_dir, Class)
  end

  describe "#initialize" do
    it "creates an error directory" do
      expect(FileUtils).to receive(:mkdir_p).with("#{dest_dir}/errors")
      described_class.new(dest_dir, Class)
    end

    it "sets up an err_file depending of the class that comes from" do
      ec_backup = described_class.new(dest_dir, Chef::Knife::EcBackup)
      expect(ec_backup.err_file).to match File.join(err_dir, "backup-1988-04-17T00:00:00+00:00.json")
      ec_restore = described_class.new(dest_dir, Chef::Knife::EcRestore)
      expect(ec_restore.err_file).to match File.join(err_dir, "restore-1988-04-17T00:00:00+00:00.json")
      ec_other = described_class.new(dest_dir, Class)
      expect(ec_other.err_file).to match File.join(err_dir, "other-1988-04-17T00:00:00+00:00.json")
    end
  end

  it "#display" do
    @knife_ec_error_handler.add(net_exception(123))
    expect { @knife_ec_error_handler.display }.to output(/
Error Summary Report
{
  "timestamp": "1988-04-17 00:00:00 \+0000",
  "message": "I'm not real!",
  "backtrace": null,
  "exception": "Net::HTTPServerException"
}
/).to_stdout
  end

  it "#add" do
    mock_content = <<-EOF
{
  "timestamp": "1988-04-17 00:00:00 +0000",
  "message": "I'm not real!",
  "backtrace": null,
  "exception": "Net::HTTPServerException"
}{
  "timestamp": "1988-04-17 00:00:00 +0000",
  "message": "I'm not real!",
  "backtrace": null,
  "exception": "Net::HTTPServerException"
}{
  "timestamp": "1988-04-17 00:00:00 +0000",
  "message": "I'm not real!",
  "backtrace": null,
  "exception": "Net::HTTPServerException"
}{
  "timestamp": "1988-04-17 00:00:00 +0000",
  "message": "I'm not real!",
  "backtrace": null,
  "exception": "Net::HTTPServerException"
}{
  "timestamp": "1988-04-17 00:00:00 +0000",
  "message": "I'm not real!",
  "backtrace": null,
  "exception": "Chef::ChefFS::FileSystem::NotFoundError"
}{
  "timestamp": "1988-04-17 00:00:00 +0000",
  "message": "I'm not real!",
  "backtrace": null,
  "exception": "Chef::ChefFS::FileSystem::OperationFailedError"
}
EOF
    err_file = @knife_ec_error_handler.err_file
    expect(Chef::JSONCompat).to receive(:to_json_pretty)
      .at_least(4)
      .and_call_original
    expect(File).to receive(:open)
      .at_least(4)
      .with(err_file, "a")
      .and_call_original
    @knife_ec_error_handler.add(net_exception(500))
    @knife_ec_error_handler.add(net_exception(409))
    @knife_ec_error_handler.add(net_exception(404))
    @knife_ec_error_handler.add(net_exception(123))
    @knife_ec_error_handler.add(cheffs_filesystem_exception('NotFoundError'))
    @knife_ec_error_handler.add(cheffs_filesystem_exception('OperationFailedError'))
    expect(File.read(err_file)).to match mock_content.strip
  end
end
