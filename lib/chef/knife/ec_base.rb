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

class Chef
  class Knife
    module EcBase
      class NoAdminFound < Exception; end

      def self.included(includer)
        includer.class_eval do

          option :concurrency,
            :long => '--concurrency THREADS',
            :description => 'Maximum number of simultaneous requests to send (default: 10)'

          option :webui_key,
            :long => '--webui-key KEYPATH',
            :description => 'Path to the WebUI Key (default: /etc/opscode/webui_priv.pem)',
            :default => '/etc/opscode/webui_priv.pem'

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

          option :sql_user,
            :long => "--sql-user USERNAME",
            :description => 'User used to connect to the postgresql database.'

          option :sql_password,
            :long => "--sql-password PASSWORD",
            :description => 'Password used to connect to the postgresql database'

          option :with_user_sql,
            :long => '--with-user-sql',
            :description => 'Try direct data base access for user export/import.  Required to properly handle passwords, keys, and USAGs'

          option :with_key_sql,
            :long => '--with-key-sql',
            :description => 'Try direct data base access for key table export/import.  Required to properly handle rotated keys.'

        end

        attr_accessor :dest_dir

        def configure_chef
          super
          Chef::Config[:concurrency] = config[:concurrency].to_i if config[:concurrency]
          Chef::ChefFS::Parallelizer.threads = (Chef::Config[:concurrency] || 10) - 1
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
        Chef::Config.client_key = config[:webui_key]
      end

      def set_dest_dir_from_args!
        if name_args.length <= 0
          ui.error("Must specify backup directory as an argument.")
          exit 1
        end
        @dest_dir = name_args[0]
      end

      def ensure_webui_key_exists!
        if !File.exist?(config[:webui_key])
          ui.error("Webui Key (#{config[:webui_key]}) does not exist.")
          exit 1
        end
      end
    end
  end
end
