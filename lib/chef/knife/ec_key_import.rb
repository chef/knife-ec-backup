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
require_relative '../org_id_cache'

class Chef
  class Knife
    class EcKeyImport < Chef::Knife

      include Knife::EcKeyBase

      banner "knife ec key import [USER_DATA_PATH] [KEY_DATA_PATH]"

      option :skip_pivotal,
        :long => "--[no-]skip-pivotal",
        :default => true,
        :boolean => true,
        :description => "Upload pivotal key.  By default the pivotal key is not uploaded."

      option :skip_ids,
        :long => "--[no-]skip-user-ids",
        :default => true,
        :boolean => true,
        :description => "Reuses user ids from the restore destination when updating existing users to avoid database conflicts."

      option :users_only,
        :long => "--users-only",
        :default => false,
        :description => "Only update users (skip client key data)"

     option :clients_only,
        :log => "--clients-only",
        :default => false,
        :description => "Only update client key data. Implies --skip-users-table"

      def run
        if config[:sql_user].nil? || config[:sql_password].nil?
          load_config_from_file!
        end

        @org_id_cache = Chef::OrgIdCache.new(db)

        # user_data_path defaults to key_dump.json to support
        # older knife-ec-backup exports
        user_data_path = @name_args[0] || "key_dump.json"
        key_data_path = @name_args[1] || "key_table_dump.json"
        import_user_data(user_data_path) unless (config[:skip_users_table] || config[:clients_only])
        import_key_data(key_data_path) unless config[:skip_keys_table]
      end

      def import_key_data(path)
        key_data = JSON.parse(File.read(path))
        key_data.each do |d|
          case d['type']
          when 'client'
            next if config[:users_only]
            insert_key_data_for_client(d)
          when 'user'
            next if config[:clients_only]
            insert_key_data_for_user(d)
          else
            ui.warn "Unkown actor type #{d['type']} for #{d['name']}"
            next
          end
        end
      end

      # If a given key_name already exists for the client, update it,
      # otherwise insert a new key into the key table.
      #
      # Unlike users, we never want to keep the internal ID from the
      # backup.
      #
      # The org_id is likely different than that stored in the backup.
      # We query the new org_id based on org_name, caching it to avoid
      # multiple lookups in a large org.
      def insert_key_data_for_client(d)
        ui.msg "Updating key data for client[#{d['name']}]"

        org_id = @org_id_cache.fetch(d['org_name'])
        if org_id.nil?
          ui.warn "Could not find organization for client[#{d['name']}], skipping."
          ui.warn "Organizations much be restored before key data can be imported."
          return
        end

        existing_client = db[:clients].where(:org_id => org_id, :name => d['name']).first
        if existing_client.nil?
          ui.warn "Did not find existing client record for #{d['name']}, skipping."
          ui.warn "Client records must be restored before key data can be imported."
          return
        end

        new_id = existing_client[:id]
        Chef::Log.debug("Found client id for #{d['name']}: #{new_id}")
        upsert_key_record(key_record_for_db(d, new_id))
      end

      # Insert key data for each user record
      #
      # When :skip_id's is set, we are not using the ids from the
      # backup.  In this case, look up the user id in the users table.
      #
      # When :skip_id's is not set, we are using the ids from the
      # backup. The update_key trigger on the users table should
      # ensure that the user ids have already been replaced and should
      # match what we have in the backup.
      def insert_key_data_for_user(d)
        if d['name'] == 'pivotal' && config[:skip_pivotal]
          ui.warn "Skipping pivotal user."
          return
        end
        ui.msg "Updating key data for user[#{d['name']}]"
        new_id = if config[:skip_ids]
                   db[:users].where(:username => d['name']).first[:id]
                 else
                   d['id']
                 end
        Chef::Log.debug("Found user id for #{d['name']}: #{new_id}")
        upsert_key_record(key_record_for_db(d, new_id))
      end

      def upsert_key_record(r)
        key_records_to_update = db[:keys].where(:key_name => r[:key_name], :id => r[:id])
        case key_records_to_update.count
        when 0
          Chef::Log.debug("No existing records found for #{r[:key_name]}, #{r[:id]}")
          db[:keys].insert(r)
        when 1
          Chef::Log.debug("1 record found for #{r[:key_name]}, #{r[:id]}")
          key_records_to_update.update(r)
        else
          ui.warn "Found too many records for actor id #{r[:id]} key #{d[:key_name]}"
          return
        end
      end

      def key_record_for_db(d, new_id=nil)
        {
          :id => new_id || d['id'],
          :key_name => d['key_name'],
          :public_key => d['public_key'],
          :key_version => d['key_version'],
          :created_at => Time.now,
          :expires_at => d['expires_at']
        }
      end

      def import_user_data(path)
        key_data = JSON.parse(File.read(path))
        knife_ec_error_handler = config[:knife_ec_error_handler]
        key_data.each do |d|
          if d['username'] == 'pivotal' && config[:skip_pivotal]
            ui.warn "Skipping pivotal user."
            next
          end

          ui.msg "Updating user record for #{d['username']}"
          users_to_update = db[:users].where(:username => d['username'])

          if users_to_update.count != 1
            ui.warn "Wrong number of users to update for #{d['username']}. Skipping"
          else
            # Remove authz id from import since this will no longer
            # be valid.
            d.delete('authz_id')
            d.delete('id') if config[:skip_ids]
            # If the hash_type in the export,
            # we are dealing with a record where the password is still in the
            # serialized_object. Explicitly setting these to nil ensures that the
            # password set in the restore is wiped out.
            unless d.has_key?('hash_type')
              d['hash_type'] = nil
              d['hashed_password'] = nil
              d['salt'] = nil
            end
            begin
              users_to_update.update(d)
            rescue => ex
              ui.warn "Could not restore user #{d['username']}"
              if ex.class == Sequel::ForeignKeyConstraintViolation
                message = "This error usually indicates that a user already exists with a different ID and is associated with one or more organizations on the target system.  The username is #{d['username']} and the ID in the backup files is #{d['id']}"
                ui.warn message
                ex = ex.exception "#{ex.message} #{message}"
              end
              knife_ec_error_handler.add(ex) if knife_ec_error_handler
            end
          end
        end
      end
    end
  end
end
