require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "spec_helper"))
require 'chef/knife/ec_error_handler'
require 'fakefs/spec_helpers'

def net_exception(code)
  s = double("status", :code => code.to_s)
  Net::HTTPServerException.new("I'm not real!", s)
end

describe Chef::Knife::EcErrorHandler do
  let(:dest_dir) { Dir.mktmpdir }

  before(:each) do
    @knife_ec_error_handler = described_class.new(dest_dir, Class)
  end

  it "#display" do
    @knife_ec_error_handler.add(net_exception(123))
    expect { @knife_ec_error_handler.display }.to output(/Error Summary Report/).to_stdout
    expect { @knife_ec_error_handler.display }.to output(/I'm not real!/).to_stdout
    expect { @knife_ec_error_handler.display }.to output(/Net::HTTPServerException/).to_stdout
  end

  it "#add" do
    @knife_ec_error_handler.add(net_exception(500))
    @knife_ec_error_handler.add(net_exception(409))
    @knife_ec_error_handler.add(net_exception(404))
    @knife_ec_error_handler.add(net_exception(123))
  end
end
