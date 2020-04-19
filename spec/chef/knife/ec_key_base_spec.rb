require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "spec_helper"))
require 'chef/knife/ec_key_base'

class KeyBaseTester < Chef::Knife
  include Chef::Knife::EcKeyBase
end

describe Chef::Knife::EcKeyBase do
  let (:knife) { KeyBaseTester.new }

  let(:running_server_postgresql_sql_config_json) {
    '{"private_chef": { "opscode-erchef":{}, "postgresql": { "sql_user": "jiminy", "sql_password": "secret"} }, "postgresql": { "sql_user": "jiminy", "sql_password": "secret"} }'
  }


  let(:running_server_erchef_config_json) {
    '{"private_chef": { "opscode-erchef": { "sql_user": "cricket", "sql_password": "secrete"}}, "opscode_erchef": { "sql_user": "cricket", "sql_password": "secrete"}}'
  }
  describe "#load_config_from_file!" do
    before(:each) do
      allow(File).to receive(:exists?).and_return(true)
      allow(File).to receive(:size).and_return(1)
    end
    it "correctly sets sql options when they live under postgresql settings" do
      allow(IO).to receive(:read).and_return(running_server_postgresql_sql_config_json)
      knife.load_config_from_file!
      expect(knife.config[:sql_user]).to eq("jiminy")
      expect(knife.config[:sql_password]).to eq("secret")
    end
    it "correctly sets sql options when they live under opscode-erchef settings" do
      allow(IO).to receive(:read).and_return(running_server_erchef_config_json)
      knife.load_config_from_file!
      expect(knife.config[:sql_user]).to eq("cricket")
      expect(knife.config[:sql_password]).to eq("secrete")
    end
  end
end
