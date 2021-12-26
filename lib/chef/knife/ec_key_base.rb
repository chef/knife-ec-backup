#
# Author:: Steven Danna (<steve@getchef.com>)
# Copyright:: Copyright (c) 2014 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/knife'
require 'veil'

class Chef
  class Knife
    module EcKeyBase

      def self.included(includer)
        includer.class_eval do

          deps do
            require 'sequel'
            require 'json' unless defined?(JSON)
            require_relative '../automate'
          end

          option :sql_host,
          :long => '--sql-host HOSTNAME',
          :description => 'PostgreSQL database hostname (default: localhost)',
          :default => "localhost"

          option :sql_port,
          :long => '--sql-port PORT',
          :description => 'PostgreSQL database port (default: 5432)',
          :default => 5432

          option :sql_db,
          :long => '--sql-db DBNAME',
          :description => 'PostgreSQL Chef Infra Server database name (default: opscode_chef or automate-cs-oc-erchef)'

          option :sql_user,
          :long => "--sql-user USERNAME",
          :description => 'User used to connect to the postgresql database.'

          option :sql_password,
          :long => "--sql-password PASSWORD",
          :description => 'Password used to connect to the postgresql database'

          option :sql_cert,
          :long => "--sql-cert ",
          :description => 'Path to client ssl cert'

          option :sql_key,
          :long => "--sql-key PATH",
          :description => 'Path to client ssl key'

          option :sql_rootcert,
          :long => "--sql-rootcert ",
          :description => 'Path to root ssl cert'

          option :secrets_file_path,
          :long => '--secrets-file PATH',
          :description => 'Path to a valid private-chef-secrets.json file (default: /etc/opscode/private-chef-secrets.json)',
          :default => '/etc/opscode/private-chef-secrets.json'

          option :skip_keys_table,
          :long => "--skip-keys-table",
          :description => "Skip Chef 12-only keys table",
          :default => false

          option :skip_users_table,
          :long => "--skip-users-table",
          :description => "Skip users table",
          :default => false
        end
      end

      def db
        @db ||= begin
                  require 'sequel'
                  require 'uri'
                  server_uri = URI('postgres://')
                  server_uri.host = config[:sql_host]
                  server_uri.port = config[:sql_port]
                  server_uri.user = URI.encode_www_form_component(config[:sql_user]) if config[:sql_user]
                  server_uri.password = URI.encode_www_form_component(config[:sql_password]) if config[:sql_password]
                  query_params = []
                  query_params.push("sslcert=#{config[:sql_cert]}") if config[:sql_cert]
                  query_params.push("sslkey=#{config[:sql_key]}") if config[:sql_key]
                  query_params.push("sslrootcert=#{config[:sql_rootcert]}") if config[:sql_rootcert]
                  server_uri.query = query_params.join("&") if query_params.length > 0

                  ::Sequel.connect(server_uri.to_s, :convert_infinite_timestamps => :string)
                end
      end

      # Loads SQL user and password from running config if not passed
      # as a command line option
      def load_config_from_file!
        if Chef::Automate.is_installed?
          ui.msg "Automate detected"
          config.merge! Chef::Automate.config {|key, v1, v2| v1}
        else
          if ! File.exists?("/etc/opscode/chef-server-running.json")
            ui.fatal "SQL User or Password not provided as option and running config cannot be found!"
            exit 1
          else
            running_config ||= JSON.parse(File.read("/etc/opscode/chef-server-running.json"))
            # Latest versions of Chef Infra Server put the database info under opscode-erchef.sql_user
            hash_key = if running_config['private_chef']['opscode-erchef'].has_key? 'sql_user'
                        'opscode-erchef'
                      else
                        'postgresql'
                      end
            config[:sql_user] ||= running_config['private_chef'][hash_key]['sql_user']
            config[:sql_password] ||= (running_config['private_chef'][hash_key]['sql_password'] || sql_password)
            config[:sql_db] ||= 'opscode_chef'
          end
        end
      end

      def veil_config
        { provider: 'chef-secrets-file',
          path: config[:secrets_file_path] }
      end

      def veil
        Veil::CredentialCollection.from_config(veil_config)
      end

      def sql_password
        if config[:sql_password]
          config[:sql_password]
        elsif veil.exist?("opscode_erchef", "sql_password")
          veil.get("opscode_erchef", "sql_password")
        else veil.exist?("postgresql", "sql_password")
          veil.get("postgresql", "sql_password")
        end
      end
    end
  end
end
