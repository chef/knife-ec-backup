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

class Chef
  class Knife
    module EcBase

      def self.included(includer)
        includer.class_eval do

          option :concurrency,
            :long => '--concurrency THREADS',
            :description => 'Maximum number of simultaneous requests to send (default: 10)'

          option :webui_key,
            :long => '--webui-key KEYPATH',
            :description => 'Path to the WebUI Key (default: /etc/opscode/webui_priv.pem)'

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

        end
      end
    end
  end
end
