require 'chef/knife'
require_relative 'ec_base'

class Chef
  class Knife
    class EcBackup < Chef::Knife

      include Knife::EcBase

      banner "knife ec backup DIRECTORY"

      deps do
        require 'chef/chef_fs/config'
        require 'chef/chef_fs/file_system'
        require 'chef/chef_fs/file_pattern'
        begin
          require 'chef/chef_fs/parallelizer'
        rescue LoadError
          require 'chef-utils/parallel_map' unless defined?(ChefUtils::ParallelMap)
        end
        require_relative '../server'
        require 'fileutils' unless defined?(FileUtils)
      end

      def run
        set_dest_dir_from_args!
        set_client_config!
        set_skip_user_acl!
        ensure_webui_key_exists!

        ensure_dir("#{dest_dir}/users")
        ensure_dir("#{dest_dir}/user_acls") unless config[:skip_useracl]
        ui.msg 'Downloading Users'
        for_each_user do |username, url|
          download_user(username, url)
          if config[:skip_useracl]
            ui.warn("Skipping user ACL download for #{username}. To download this ACL, remove --skip-useracl or upgrade your Enterprise Chef Server.")
          else
            download_user_acl(username)
          end
        end
        purge_users_on_backup

        if config[:with_user_sql] || config[:with_key_sql]
          export_from_sql
        end

        ensure_dir("#{dest_dir}/organizations")
        for_each_organization do |org_object|
          name = org_object['name']
          write_org_object_to_disk(org_object)
          download_org_data(name)
          download_org_members(name)
          download_org_invitations(name)
        end

        warn_on_incorrect_clients_group(dest_dir, "backup")

        completion_banner
      end

      def users_for_purge
        purge_list = local_user_list - remote_user_list
        # failsafe - don't delete pivotal
        purge_list -= ['pivotal']
        purge_list.each do |user|
          yield user
        end
      end

      def purge_users_on_backup
        return unless config[:purge]
        users_for_purge do |user|
          ui.msg "Deleting user #{user} from local backup (purge is on)"
          begin
            ::File.delete("#{dest_dir}/users/#{user}.json")
            ::File.delete("#{dest_dir}/user_acls/#{user}.json")
          rescue Errno::ENOENT => e
            ui.warn "Failed to find local #{user} data #{e}"
          end
        end
      end

      def for_each_user
        remote_users.each_pair do |name, url|
          yield name, url
        end
      rescue Net::HTTPServerException => ex
        knife_ec_error_handler.add(ex)
      end

      def for_each_organization
        rest.get('/organizations').each_pair do |name, url|
          next unless (config[:org].nil? || config[:org] == name)
          ui.msg "Downloading organization object for #{name} from #{url}"
          begin
            org = rest.get(url)
          rescue Net::HTTPServerException => ex
            ui.error "Failed to find organization '#{name}'."
            knife_ec_error_handler.add(ex)
            next
          end
          # Enterprise Chef 11 and below uses a pool of pre-created
          # organizations to account for slow organization creation
          # using CouchDB. Thus, on server versions < 12 we want to
          # skip any of these pre-created organizations by checking if
          # they have been assigned or not.  The Chef 12 API does not
          # return an assigned_at field.
          if org['assigned_at'] || server.version >= Gem::Version.new("12")
            yield org
          else
            ui.msg "Skipping pre-created org #{name}"
          end
        end
      end

      def download_user(username, url)
        File.open("#{dest_dir}/users/#{username}.json", 'w') do |file|
          file.write(Chef::JSONCompat.to_json_pretty(rest.get(url)))
        end
      rescue Net::HTTPServerException => ex
        knife_ec_error_handler.add(ex)
      end

      def download_user_acl(username)
        File.open("#{dest_dir}/user_acls/#{username}.json", 'w') do |file|
          file.write(Chef::JSONCompat.to_json_pretty(user_acl_rest.get("users/#{username}/_acl")))
        end
      rescue Net::HTTPServerException => ex
        knife_ec_error_handler.add(ex)
      end

      def export_from_sql
        require_relative 'ec_key_export'
        Chef::Knife::EcKeyExport.deps
        k = Chef::Knife::EcKeyExport.new
        k.name_args = ["#{dest_dir}/key_dump.json", "#{dest_dir}/key_table_dump.json"]
        k.config[:sql_host] = config[:sql_host]
        k.config[:sql_port] = config[:sql_port]
        k.config[:sql_db] = config[:sql_db]
        k.config[:sql_user] = config[:sql_user]
        k.config[:sql_password] = config[:sql_password]
        k.config[:skip_users_table] = !config[:with_user_sql]
        k.config[:skip_keys_table] = !config[:with_key_sql]
        k.run
      end

      def write_org_object_to_disk(org_object)
        name = org_object['name']
        ensure_dir("#{dest_dir}/organizations/#{name}")
        File.open("#{dest_dir}/organizations/#{name}/org.json", 'w') do |file|
          file.write(Chef::JSONCompat.to_json_pretty(org_object))
        end
      end

      def download_org_members(name)
        ensure_dir("#{dest_dir}/organizations/#{name}")
        File.open("#{dest_dir}/organizations/#{name}/members.json", 'w') do |file|
          file.write(Chef::JSONCompat.to_json_pretty(rest.get("/organizations/#{name}/users")))
        end
      rescue Net::HTTPServerException => ex
        knife_ec_error_handler.add(ex)
      end

      def download_org_invitations(name)
        ensure_dir("#{dest_dir}/organizations/#{name}")
        File.open("#{dest_dir}/organizations/#{name}/invitations.json", 'w') do |file|
          file.write(Chef::JSONCompat.to_json_pretty(rest.get("/organizations/#{name}/association_requests")))
        end
      rescue Net::HTTPServerException => ex
        knife_ec_error_handler.add(ex)
      end

      def ensure_dir(dir)
        if !File.exist?(dir)
          FileUtils.mkdir_p(dir)
        end
      end

      PATHS = %w(chef_repo_path cookbook_path environment_path data_bag_path role_path node_path client_path acl_path group_path container_path)
      def download_org_data(name)
        old_config = Chef::Config.save

        begin
          # Clear out paths
          PATHS.each do |path|
            Chef::Config.delete(path.to_sym)
          end
          Chef::Config.chef_repo_path = "#{dest_dir}/organizations/#{name}"
          Chef::Config.versioned_cookbooks = true

          Chef::Config.chef_server_url = "#{server.root_url}/organizations/#{name}"

          ensure_dir(Chef::Config.chef_repo_path)

          # Download the billing-admins, public_key_read_access ACL and group as pivotal
          chef_fs_config = Chef::ChefFS::Config.new

          paths = ['/acls/groups/billing-admins.json', '/groups/billing-admins.json', '/groups/admins.json']
          paths.push('/acls/groups/public_key_read_access.json', '/groups/public_key_read_access.json') if server.supports_public_key_read_access?

          paths.each do |path|
            chef_fs_copy_pattern(path, chef_fs_config)
          end

          Chef::Config.node_name = if config[:skip_version]
                                     org_admin
                                   else
                                     server.supports_defaulting_to_pivotal? ? 'pivotal' : org_admin
                                   end

          chef_fs_config = Chef::ChefFS::Config.new
          top_level_paths = chef_fs_config.chef_fs.children.select { |entry| entry.name != 'acls' && entry.name != 'groups' }.map { |entry| entry.path }

          # The top level acl object names end with .json extension
          # Therefore we can use Chef::ChefFS::FilePattern matching for items
          # such as /acls/organizations.json
          #
          # 2nd level leaf /acl/*/* objects as well as /groups/* objects do not end with .json
          # therefore we use normalize_path_name to add the .json extension
          # for example: /acls/environments/_default

           # Skip the billing-admins, public_key_read_access group ACLs and the groups since they've already been copied
          exclude_list = ['billing-admins', 'public_key_read_access']

          top_level_acls  = chef_fs_paths('/acls/*.json', chef_fs_config, [])
          acl_paths       = chef_fs_paths('/acls/*/*', chef_fs_config, exclude_list)
          group_paths     = chef_fs_paths('/groups/*', chef_fs_config, exclude_list)
          (top_level_paths + top_level_acls + acl_paths + group_paths).each do |path|
            chef_fs_copy_pattern(path, chef_fs_config)
          end
        ensure
          Chef::Config.restore(old_config)
        end
      end

      def normalize_path_name(path)
        path=~/\.json\z/ ? path : path<<'.json'
      end

      def chef_fs_paths(pattern_str, chef_fs_config, exclude=[])
        pattern = Chef::ChefFS::FilePattern.new(pattern_str)
        list = Chef::ChefFS::FileSystem.list(chef_fs_config.chef_fs, pattern)
        list = list.select { |entry| ! exclude.include?(entry.name) } if ! exclude.empty?
        list.map { |entry| normalize_path_name(entry.path) }
      end

      def chef_fs_copy_pattern(pattern_str, chef_fs_config)
        ui.msg "Copying #{pattern_str}"
        pattern = Chef::ChefFS::FilePattern.new(pattern_str)
        Chef::ChefFS::FileSystem.copy_to(pattern, chef_fs_config.chef_fs,
                                         chef_fs_config.local_fs, nil,
                                         config, ui,
                                         proc { |entry| chef_fs_config.format_path(entry) })
      rescue Net::HTTPServerException,
             Chef::ChefFS::FileSystem::NotFoundError,
             Chef::ChefFS::FileSystem::OperationFailedError => ex
        knife_ec_error_handler.add(ex)
      end
    end
  end
end
