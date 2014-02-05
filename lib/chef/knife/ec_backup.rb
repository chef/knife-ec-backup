require 'chef/knife'

class Chef
  class Knife
    class EcBackup < Chef::Knife
      banner 'knife ec backup'

      include Knife::EcBase

      deps do
        require 'chef_fs/config'
        require 'chef_fs/file_system'
        require 'chef_fs/file_pattern'
        require 'chef_fs/parallelizer'
      end

      def run
        # Check for destination directory argument
        if name_args.length <= 0
          ui.error('Must specify backup directory as an argument.')
          exit 1
        end

        dest_dir = name_args[0]
        set_client_config!

        webui_key = config[:webui_key]
        assert_exists!(webui_key)

        rest = Chef::REST.new(Chef::Config.chef_server_root)

        user_acl_rest = setup_user_acl_rest! unless config[:skip_useracl]

        # Grab users
        ui.msg 'Grabbing users ...'

        ensure_dir("#{dest_dir}/users")
        ensure_dir("#{dest_dir}/user_acls")

        rest.get_rest('/users').each_pair do |name, url|
          File.open("#{dest_dir}/users/#{name}.json", 'w') do |file|
            file.write(Chef::JSONCompat.to_json_pretty(rest.get_rest(url)))
          end

          if config[:skip_useracl]
            ui.warn("Skipping user ACL download for #{name}. To download this ACL, remove --skip-useracl or upgrade your Enterprise Chef Server.")
            next
          end

          File.open("#{dest_dir}/user_acls/#{name}.json", 'w') do |file|
            file.write(Chef::JSONCompat.to_json_pretty(user_acl_rest.get_rest("users/#{name}/_acl")))
          end
        end

        # Download organizations
        ensure_dir("#{dest_dir}/organizations")
        error = false
        rest.get_rest('/organizations').each_pair do |name, url|
          org = rest.get_rest(url)
          if org['assigned_at']
            ui.msg 'Grabbing organization #{name} ...'
            ensure_dir("#{dest_dir}/organizations/#{name}")
            error = download_org(dest_dir, webui_key, name) || error
            File.open("#{dest_dir}/organizations/#{name}/org.json", 'w') do |file|
              file.write(Chef::JSONCompat.to_json_pretty(org))
            end
            File.open("#{dest_dir}/organizations/#{name}/members.json", 'w') do |file|
              file.write(Chef::JSONCompat.to_json_pretty(rest.get_rest("#{url}/users")))
            end
            File.open("#{dest_dir}/organizations/#{name}/invitations.json", 'w') do |file|
              file.write(Chef::JSONCompat.to_json_pretty(rest.get_rest("#{url}/association_requests")))
            end
          end
        end

        exit 1 if error
      end

      def ensure_dir(dir)
        Dir.mkdir(dir) unless File.exist?(dir)
      end

      PATHS = %w(chef_repo_path cookbook_path environment_path data_bag_path role_path node_path client_path acl_path group_path container_path)
      CONFIG_VARS = %w(chef_server_url chef_server_root custom_http_headers node_name client_key versioned_cookbooks) + PATHS
      def download_org(dest_dir, webui_key, name)
        old_config = {}
        error = false
        CONFIG_VARS.each do |key|
          old_config[key] = Chef::Config[key.to_sym]
        end
        begin
          # Clear out paths
          PATHS.each do |path_var|
            Chef::Config[path_var.to_sym] = nil
          end
          Chef::Config.chef_repo_path = "#{dest_dir}/organizations/#{name}"
          Chef::Config.versioned_cookbooks = true

          Chef::Config.chef_server_url = "#{Chef::Config.chef_server_root}/organizations/#{name}"

          ensure_dir(Chef::Config.chef_repo_path)

          # Download the billing-admins ACL and group as pivotal
          chef_fs_config = ::ChefFS::Config.new
          ['/acls/groups/billing-admins.json', '/groups/billing-admins.json', '/groups/admins.json'].each do |path|
            pattern = ::ChefFS::FilePattern.new(path)
            error = ::ChefFS::FileSystem.copy_to(pattern, chef_fs_config.chef_fs, chef_fs_config.local_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) }) || error
          end

          # Figure out who the admin is so we can spoof him and retrieve his stuff
          rest = Chef::REST.new(Chef::Config.chef_server_url)
          admin_users = rest.get_rest('groups/admins')['users']
          org_members = rest.get_rest('users').map { |user| user['user']['username'] }
          admin_users.delete_if { |user| !org_members.include?(user) }
          Chef::Config.node_name = admin_users[0]
          Chef::Config.client_key = webui_key
          Chef::Config.custom_http_headers = (Chef::Config.custom_http_headers || {}).merge('x-ops-request-source' => 'web')

          # Download the entire org skipping the billing admins group ACL and the group itself
          chef_fs_config = ::ChefFS::Config.new
          top_level_paths = chef_fs_config.chef_fs.children.select { |entry| entry.name != 'acls' && entry.name != 'groups' }.map { |entry| entry.path }
          acl_paths = ::ChefFS::FileSystem.list(chef_fs_config.chef_fs, ::ChefFS::FilePattern.new('/acls/*')).select { |entry| entry.name != 'groups' }.map { |entry| entry.path }
          group_acl_paths = ::ChefFS::FileSystem.list(chef_fs_config.chef_fs, ::ChefFS::FilePattern.new('/acls/groups/*')).select { |entry| entry.name != 'billing-admins.json' }.map { |entry| entry.path }
          group_paths = ::ChefFS::FileSystem.list(chef_fs_config.chef_fs, ::ChefFS::FilePattern.new('/groups/*')).select { |entry| entry.name != 'billing-admins.json' }.map { |entry| entry.path }

          (top_level_paths + group_acl_paths + acl_paths + group_paths).each do |path|
            error = ::ChefFS::FileSystem.copy_to(::ChefFS::FilePattern.new(path), chef_fs_config.chef_fs, chef_fs_config.local_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) }) || error
          end
          error
        ensure
          CONFIG_VARS.each do |key|
            Chef::Config[key.to_sym] = old_config[key]
          end
        end
      end
    end
  end
end
