require 'chef/knife'
require 'chef/knife/ec_base'

class Chef
  class Knife
    class EcBackup < Chef::Knife

      include Knife::EcBase

      banner "knife ec backup DIRECTORY"

      deps do
        require 'chef/chef_fs/config'
        require 'chef/chef_fs/file_system'
        require 'chef/chef_fs/file_pattern'
        require 'chef/chef_fs/parallelizer'
        require 'chef/server'
        require 'fileutils'
      end

      def run
        set_dest_dir_from_args!
        set_client_config!
        set_skip_user_acl!
        ensure_webui_key_exists!

        ensure_dir("#{dest_dir}/users")
        ensure_dir("#{dest_dir}/user_acls") unless config[:skip_useracl]
        ui.msg "Downloading Users"
        remote_users = []
        for_each_user do |username, url|
          remote_users.push(username.to_sym)
          download_user(username, url)
          if config[:skip_useracl]
            ui.warn("Skipping user ACL download for #{username}. To download this ACL, remove --skip-useracl or upgrade your Enterprise Chef Server.")
          else
            download_user_acl(username)
          end
        end
        purge_users(remote_users) if config[:purge]

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
      end

      def purge_users(src)
        local_users = Dir.glob("#{dest_dir}/users/*\.json").map { |u| File.basename(u, '.json').to_sym }
        purge_list = local_users - src
        # failsafe - don't delete pivotal
        purge_list -= [:pivotal]
        purge_list.collect(&:to_s).each do |user|
          ui.msg "Deleting local user #{user} from backup (purge in on)"
          begin
            File.delete("#{dest_dir}/users/#{user}.json")
            File.delete("#{dest_dir}/user_acls/#{user}.json")
          rescue Errno::ENOENT
            true
          end
        end
      end

      def for_each_user
        rest.get('/users').each_pair do |name, url|
          yield name, url
        end
      end

      def for_each_organization
        rest.get('/organizations').each_pair do |name, url|
          next unless (config[:org].nil? || config[:org] == name)
          ui.msg "Downloading organization object for #{name} from #{url}"
          org = rest.get(url)
          # Enterprise Chef 11 and below uses a pool of precreated
          # organizations to account for slow organization creation
          # using CouchDB. Thus, on server versions < 12 we want to
          # skip any of these precreated organizations by checking if
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
      end

      def download_user_acl(username)
        File.open("#{dest_dir}/user_acls/#{username}.json", 'w') do |file|
          file.write(Chef::JSONCompat.to_json_pretty(user_acl_rest.get("users/#{username}/_acl")))
        end
      end

      def export_from_sql
        require 'chef/knife/ec_key_export'
        Chef::Knife::EcKeyExport.deps
        k = Chef::Knife::EcKeyExport.new
        k.name_args = ["#{dest_dir}/key_dump.json", "#{dest_dir}/key_table_dump.json"]
        k.config[:sql_host] = config[:sql_host]
        k.config[:sql_port] = config[:sql_port]
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
      end

      def download_org_invitations(name)
        ensure_dir("#{dest_dir}/organizations/#{name}")
        File.open("#{dest_dir}/organizations/#{name}/invitations.json", 'w') do |file|
          file.write(Chef::JSONCompat.to_json_pretty(rest.get("/organizations/#{name}/association_requests")))
        end
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
          chef_fs_copy_pattern('/acls/groups/billing-admins.json', chef_fs_config)
          chef_fs_copy_pattern('/groups/billing-admins.json', chef_fs_config)
          chef_fs_copy_pattern('/acls/groups/public_key_read_access.json', chef_fs_config)
          chef_fs_copy_pattern('/groups/public_key_read_access.json', chef_fs_config)
          chef_fs_copy_pattern('/groups/admins.json', chef_fs_config)

          # Set Chef::Config to use an organization administrator
          Chef::Config.node_name = org_admin

          # Download the entire org skipping the billing-admins, public_key_read_access group ACLs and the groups themselves
          chef_fs_config = Chef::ChefFS::Config.new
          top_level_paths = chef_fs_config.chef_fs.children.select { |entry| entry.name != 'acls' && entry.name != 'groups' }.map { |entry| entry.path }
          acl_paths       = chef_fs_paths('/acls/*', chef_fs_config, ['groups'])
          group_acl_paths = chef_fs_paths('/acls/groups/*', chef_fs_config, ['billing-admins','public_key_read_access'])
          group_paths     = chef_fs_paths('/groups/*', chef_fs_config, ['billing-admins','public_key_read_access'])
          (top_level_paths + group_acl_paths + acl_paths + group_paths).each do |path|
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
      end
    end
  end
end
