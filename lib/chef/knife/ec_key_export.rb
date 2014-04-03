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
    class EcKeyExport < Chef::Knife

      include Knife::EcKeyBase

      banner "knife ec key export [PATH]"

      def run
        if config[:sql_user].nil? || config[:sql_password].nil?
          load_config_from_file!
        end

        path = @name_args[0] || "key_dump.json"
        export(path)
      end

      def export(path)
        users = db.select(:username, :public_key, :pubkey_version, :hashed_password, :salt, :hash_type).from(:users)
        File.open(path, 'w') { |file| file.write(users.all.to_json) }
      end
    end
  end
end
