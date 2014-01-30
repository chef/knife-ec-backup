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
    module EcKeyBase

      def self.included(includer)
        includer.class_eval do

          deps do
            require 'sequel'
            require 'json'
          end

          option :sql_host,
          :long => '--sql-host HOSTNAME',
          :descrption => 'Postgresql database hostname (default: localhost)',
          :default => "localhost"

          option :sql_port,
          :long => '--sql-host HOSTNAME',
          :descrption => 'Postgresql database port (default: 5432)',
          :default => 5432

          option :sql_user,
          :long => "--sql-user USERNAME",
          :descrption => 'User used to connect to the postgresql database.'

          option :sql_password,
          :long => "--sql-user USERNAME",
          :descrption => 'User used to connect to the postgresql database'
        end
      end

      def db
        @db ||= begin
                  server_string = "#{config[:sql_user]}:#{config[:sql_password]}@#{config[:sql_host]}:#{config[:sql_port]}/opscode_chef"
                  Sequel.connect("postgres://#{server_string}")
                end
      end

      # Loads SQL user and password from running config if not passed
      # as a command line option
      def load_config_from_file!
        if ! File.exists?("/etc/opscode/chef-server-running.json")
          ui.fatal "SQL User or Password not provided as option and running config cannot be found!"
          exit 1
        else
          running_config ||= JSON.parse(File.read("/etc/opscode/chef-server-running.json"))
          config[:sql_user] ||= running_config['private_chef']['postgresql']['sql_user']
          config[:sql_password] ||= running_config['private_chef']['postgresql']['sql_password']
        end
      end
    end
  end
end
