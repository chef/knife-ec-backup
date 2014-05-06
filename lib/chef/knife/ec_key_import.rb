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
require 'chef/knife/ec_key_base'

class Chef
  class Knife
    class EcKeyImport < Chef::Knife

      include Knife::EcKeyBase

      banner "knife ec key import [PATH]"

      option :skip_pivotal,
        :long => "--[no-]skip-pivotal",
        :default => true,
        :boolean => true,
        :description => "Upload pivotal key.  By default the pivotal key is not uploaded."

      option :skip_ids,
        :long => "--[no-]skip-user-ids",
        :default => true,
        :boolean => true,
        :description => "Upload user ids."

      def run
        if config[:sql_user].nil? || config[:sql_password].nil?
          load_config_from_file!
        end

        path = @name_args[0] || "key_dump.json"
        import(path)
      end


      def import(path)
        key_data = JSON.parse(File.read(path))
        key_data.each do |d|
          id = d['id']
          username = d['username']
          key = d['public_key']
          version = d['pubkey_version']
          hashed_password = d['hashed_password']
          hash_type = d['hash_type']
          salt = d['salt']

          if username == 'pivotal' && config[:skip_pivotal]
            ui.warn "Skipping pivotal user."
            next
          end

          ui.msg "Updating key for #{username}"
          users_to_update = db[:users].where(:username => username)
          if users_to_update.count != 1
            ui.warn "Wrong number of users to update for #{username}. Skipping"
          else
            data = { :public_key => key,
              :pubkey_version => version,
              :salt => salt,
              :hashed_password => hashed_password,
              :hash_type => hash_type
            }
            data[:id] = id unless config[:skip_ids]
            users_to_update.update(data)
          end
        end
      end
    end
  end
end
