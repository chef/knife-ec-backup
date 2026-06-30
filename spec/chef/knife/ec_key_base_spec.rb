require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "spec_helper"))
require 'chef/knife/ec_key_base'
require 'chef/automate'
require 'sequel'

class KeyBaseTester < Chef::Knife
  include Chef::Knife::EcKeyBase
end

describe Chef::Knife::EcKeyBase do
  let (:knife) { KeyBaseTester.new }

  let(:running_server_postgresql_sql_config_json) {
    '{"private_chef": { "opscode-erchef":{}, "postgresql": { "sql_user": "jiminy", "sql_password": "secret"} } }'
  }


  let(:running_server_erchef_config_json) {
    '{"private_chef": { "opscode-erchef": { "sql_user": "cricket", "sql_password": "secrete"} } }'
  }
  describe "#load_config_from_file!" do
    before(:each) do
      allow(Chef::Automate).to receive(:is_installed?).and_return(false)
      allow(File).to receive(:exists?).and_return(true)
      allow(File).to receive(:size).and_return(1)
    end
    ## skipping status test because of the missing file in automate - /etc/opscode/chef-server-running.json
    ## adding smoke tag or else all the test will be considered skipping only the status test
    it "correctly sets sql options when they live under postgresql settings", :smoke do
      allow(IO).to receive(:read).and_return(running_server_postgresql_sql_config_json)
      knife.load_config_from_file!
      expect(knife.config[:sql_user]).to eq("jiminy")
      expect(knife.config[:sql_password]).to eq("secret")
    end
    it "correctly sets sql options when they live under opscode-erchef settings", :smoke do
      allow(IO).to receive(:read).and_return(running_server_erchef_config_json)
      knife.load_config_from_file!
      expect(knife.config[:sql_user]).to eq("cricket")
      expect(knife.config[:sql_password]).to eq("secrete")
    end
  end

  # Regression coverage for the external-PostgreSQL bug: the SQL host/port must
  # be sourced from chef-server-running.json (like sql_user/sql_password/sql_db),
  # while an explicit --sql-host / --sql-port supplied on the CLI must still win.
  describe "#load_config_from_file! PostgreSQL host/port autoconfiguration" do
    let(:external_pg_running_config) {
      '{"private_chef": { "opscode-erchef": {}, "postgresql": { "vip": "db.external.example.com", "port": 6432, "sql_user": "jiminy", "sql_password": "secret" } } }'
    }

    before(:each) do
      allow(Chef::Automate).to receive(:is_installed?).and_return(false)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with("/etc/opscode/chef-server-running.json").and_return(true)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with("/etc/opscode/chef-server-running.json").and_return(external_pg_running_config)
    end

    it "adopts the PostgreSQL host and port from chef-server-running.json when no CLI flag is given" do
      knife.load_config_from_file!
      expect(knife.config[:sql_host]).to eq("db.external.example.com")
      expect(knife.config[:sql_port]).to eq(6432)
    end

    it "lets an explicit --sql-host / --sql-port win over the autoconfigured value" do
      knife.config[:sql_host] = "cli-host.example.com"
      knife.config[:sql_port] = 2345
      knife.load_config_from_file!
      expect(knife.config[:sql_host]).to eq("cli-host.example.com")
      expect(knife.config[:sql_port]).to eq(2345)
    end
  end

  # Regression coverage for #181: the configured database name must be written
  # into the PostgreSQL connection URI. It was previously resolved but never
  # applied, so PostgreSQL silently fell back to a database named after the user.
  describe "#db connection URI" do
    before(:each) do
      # Capture the connection string instead of opening a real connection.
      allow(Sequel).to receive(:connect) { |uri, *| uri }
    end

    it "includes the configured database name in the connection URI" do
      knife.config[:sql_db] = "custom_db"
      expect(knife.db).to include("/custom_db")
    end

    it "falls back to localhost:5432 when host and port are unset" do
      expect(knife.db).to start_with("postgres://localhost:5432")
    end
  end
end
