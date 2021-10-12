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
require 'chef/server_api'
require 'veil' unless defined?(Veil)
require_relative 'ec_error_handler'
require 'ffi_yajl' unless defined?(FFI_Yajl)
require_relative '../automate'

class Chef
  class Knife
    module EcBase
      class NoAdminFound < Exception; end
      class UnImplemented < Exception; end

      def self.included(includer)
        includer.class_eval do

          option :error_log_dir,
            :long => '--error-log-dir PATH',
            :description => 'Path to a directory where any errors will be logged'

          option :concurrency,
            :long => '--concurrency THREADS',
            :description => 'Maximum number of simultaneous requests to send (default: 10)'

          option :webui_key,
            :long => '--webui-key KEYPATH',
            :description => 'Path to the WebUI Key (default: Read from secrets store or /etc/opscode/webui_priv.pem or /hab/svc/automate-cs-oc-erchef/data/webui_priv.pem)'

          option :secrets_file_path,
            :long => '--secrets-file PATH',
            :description => 'Path to a valid private-chef-secrets.json file (default: /etc/opscode/private-chef-secrets.json)',
            :default => '/etc/opscode/private-chef-secrets.json'

          option :skip_useracl,
            :long => '--skip-useracl',
            :boolean => true,
            :default => false,
            :description => "Skip downloading/restoring User ACLs.  This is required for EC 11.0.2 and lower"

          option :skip_version,
            :long => '--skip-version-check',
            :boolean => true,
            :default => false,
            :description => "Skip Chef Server version check.  This will also skip any auto-configured options"

          option :org,
            :long => "--only-org ORG",
            :description => "Only download/restore objects in the named organization (default: all orgs)"

          option :sql_host,
            :long => '--sql-host HOSTNAME',
            :description => 'Postgresql database hostname (default: localhost)',
            :default => "localhost"

          option :sql_port,
            :long => '--sql-port PORT',
            :description => 'Postgresql database port (default: 5432)',
            :default => 5432

          option :sql_db,
            :long => '--sql-db DBNAME',
            :description => 'Postgresql Chef Server database name (default: opscode_chef or automate-cs-oc-erchef)'

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

          option :with_user_sql,
            :long => '--with-user-sql',
            :description => 'Try direct data base access for user export/import.  Required to properly handle passwords, keys, and USAGs'

          option :with_key_sql,
            :long => '--with-key-sql',
            :description => 'Try direct data base access for key table export/import.  Required to properly handle rotated keys.'

          option :purge,
            :long => '--purge',
            :boolean => true | false,
            :default => false,
            :description => 'Syncs deletions from backup source to restore destination.'

          option :dry_run,
            :long => '--dry-run',
            :boolean => true | false,
            :default => false,
            :description => 'Report what actions would be taken without performing any.'
        end

        attr_accessor :dest_dir

        def configure_chef
          super
          Chef::Config[:concurrency] = config[:concurrency].to_i if config[:concurrency]
          if defined?(Chef::ChefFS::Parallelizer)
            Chef::ChefFS::Parallelizer.threads = (Chef::Config[:concurrency] || 10) - 1
          elsif defined?(ChefUtils::DefaultThreadPool)
            ChefUtils::DefaultThreadPool.instance.threads = (Chef::Config[:concurrency] || 10) - 1
          end
        end

        def org_admin
          rest = Chef::ServerAPI.new(Chef::Config.chef_server_url, {:api_version => "0"})
          admin_users = rest.get('groups/admins')['users']
          org_members = rest.get('users').map { |user| user['user']['username'] }
          admin_users.delete_if { |user| !org_members.include?(user) || user == 'pivotal' }
          if admin_users.empty?
            raise Chef::Knife::EcBase::NoAdminFound
          else
            admin_users[0]
          end
        rescue Net::HTTPServerException => ex
          knife_ec_error_handler.add(ex)
        end
      end

      def server
        @server ||= if Chef::Config.chef_server_root.nil?
                      ui.warn("chef_server_root not found in knife configuration; using chef_server_url")
                      Chef::Server.from_chef_server_url(Chef::Config.chef_server_url)
                    else
                      Chef::Server.new(Chef::Config.chef_server_root)
                    end
      end

      # Since knife-ec-backup hasn't been updated to use API V1 keys endpoints
      # we should explicitly as for V0.
      def rest
        @rest ||= Chef::ServerAPI.new(server.root_url, {:api_version => "0"})
      end

      def remote_users
        @remote_users ||= rest.get('/users')
      end

      def remote_user_list
        @remote_user_list ||= remote_users.keys
      end

      def local_user_list
        @local_user_list ||= Dir.glob("#{dest_dir}/users/*\.json").map { |u| File.basename(u, '.json') }
      end

      def users_for_purge
        # not itended to be called from ec_base
        raise Chef::Knife::EcBase::UnImplemented
      end

      def knife_ec_error_handler
        error_dir = config[:error_log_dir] || dest_dir
        @knife_ec_error_handler ||= Chef::Knife::EcErrorHandler.new(error_dir, self.class)
      end

      def user_acl_rest
        @user_acl_rest ||= if config[:skip_version]
                             rest
                           elsif server.supports_user_acls?
                             rest
                           elsif server.direct_account_access?
                             Chef::ServerAPI.new("http://127.0.0.1:9465", {:api_version => "0"})
                           end

      end

      def set_skip_user_acl!
        config[:skip_useracl] ||= !(server.supports_user_acls? || server.direct_account_access?)
      end

      def set_client_config!
        Chef::Config.custom_http_headers = (Chef::Config.custom_http_headers || {}).merge({'x-ops-request-source' => 'web'})
        Chef::Config.node_name = 'pivotal'
        Chef::Config.client_key = webui_key
      end

      def set_dest_dir_from_args!
        if name_args.length <= 0
          ui.error("Must specify backup directory as an argument.")
          exit 1
        end
        @dest_dir = name_args[0]
      end

      def webui_key
        if config[:webui_key]
          config[:webui_key]
        elsif Chef::Automate.is_installed?
          config[:webui_key] = Chef::Automate.config[:webui_key]
        elsif veil.exist?("chef-server", "webui_key")
          temporary_webui_key
        else
          '/etc/opscode/webui_priv.pem'
        end
      end

      def veil_config
        { provider: 'chef-secrets-file',
          path: config[:secrets_file_path] }
      end

      def veil
        Veil::CredentialCollection.from_config(veil_config)
      end

      def temporary_webui_key
        @temp_webui_key ||= begin
                              key_data = veil.get("chef-server", "webui_key")
                              f = Tempfile.new("knife-ec-backup")
                              f.write(key_data)
                              f.flush
                              f.close
                              f
                            end
        @temp_webui_key.path
      end

      def ensure_webui_key_exists!
        if !File.exist?(webui_key)
          ui.error("Webui Key (#{config[:webui_key]}) does not exist.")
          exit 1
        end
      end

      def warn_on_incorrect_clients_group(dir, op)
        orgs = Dir[::File.join(dir, 'organizations', '*')].map { |d| ::File.basename(d) }
        orgs.each do |org|
          clients_path = ::File.expand_path(::File.join(dir, 'organizations', org, 'clients'))
          clients_in_org = Dir[::File.join(clients_path, '*')].map { |d| ::File.basename(d, '.json') }
          clients_group_path = ::File.expand_path(::File.join(dir, 'organizations', org, 'groups', 'clients.json'))
          existing_group_data = FFI_Yajl::Parser.parse(::File.read(clients_group_path), symbolize_names: false)
          existing_group_data['clients'] = [] unless existing_group_data.key?('clients')
          if existing_group_data['clients'].length != clients_in_org.length
            ui.warn "There are #{(existing_group_data['clients'].length - clients_in_org.length).abs} missing clients in #{org}'s client group file #{clients_group_path}. If this is not intentional do NOT proceed with a restore until corrected. `knife tidy backup clean` will auto-correct this. https://github.com/chef-customers/knife-tidy"
            ui.confirm("\nDo you still wish to continue with the restore?") if op == "restore"
          end
        end
      end

      def completion_banner
        puts "#{ui.color("** Finished **", :magenta)}"
      end
    end
  end
end
