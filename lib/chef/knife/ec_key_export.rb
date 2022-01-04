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
require_relative 'ec_key_base'

class Chef
  class Knife
    class EcKeyExport < Chef::Knife

      include Knife::EcKeyBase

      banner "knife ec key export [USER_DATA_PATH] [KEY_DATA_PATH]"

      def run
        if config[:sql_user].nil? || config[:sql_password].nil?
          load_config_from_file!
        end

        # user_data_path defaults to key_dump.json to support
        # older knife-ec-backup exports
        user_data_path = @name_args[0] || "key_dump.json"
        key_data_path =  @name_args[1] || "key_table_dump.json"

        export(:users, user_data_path) unless config[:skip_users_table]

        begin
          export_keys(key_data_path) unless config[:skip_keys_table]
        rescue Sequel::DatabaseError => e
          if e.message =~ /^PG::UndefinedTable/
            ui.error "Keys table not found. The keys table only exists on Chef Infra Server 12."
            ui.error "Chef Infra Server 11 users should use the --skip-keys-table option to avoid this error."
            exit 1
          else
            raise
          end
        end
      end

      def export_keys(path)
        data = db.fetch('SELECT keys_by_name.*, orgs.name AS "org_name" FROM keys_by_name LEFT JOIN orgs ON keys_by_name.org_id=orgs.id')
        File.open(path, 'w') { |file| file.write(data.all.to_json) }
      end

      def export(table, path)
        data = db.select.from(table)
        File.open(path, 'w') { |file| file.write(data.all.to_json) }
      end
    end
  end
end
