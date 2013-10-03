require 'chef/knife'

class Chef
  class Knife
    class EcBackup < Chef::Knife
      banner "knife ec backup"

      deps do
        require 'chef_fs/config'
        require 'chef_fs/file_system'
        require 'chef_fs/file_pattern'
      end

      def run
        if name_args.length == 0
          ui.error("Must specify backup directory as argument.")
          exit 1
        end

        dest_dir = name_args[0]
        webui_key = name_args[1]
        rest = Chef::REST.new(Chef::Config.chef_server_url)
        if name_args.length >= 3
          user_acl_rest = Chef::REST.new(name_args[2])
        else
          user_acl_rest = rest
        end

        # Grab users
        puts "Grabbing users ..."
        ensure_dir("#{dest_dir}/users")
        ensure_dir("#{dest_dir}/user_acls")

        rest.get_rest('/users').each_pair do |name, url|
          File.open("#{dest_dir}/users/#{name}.json", 'w') do |file|
            file.write(Chef::JSONCompat.to_json_pretty(rest.get_rest(url)))
          end
          File.open("#{dest_dir}/user_acls/#{name}.json", 'w') do |file|
            file.write(Chef::JSONCompat.to_json_pretty(user_acl_rest.get_rest("users/#{name}/_acl")))
          end
        end

        # Download organizations
        ensure_dir("#{dest_dir}/organizations")
        rest.get_rest('/organizations').each_pair do |name, url|
          org = rest.get_rest(url)
          if org['assigned_at']
            puts "Grabbing organization #{name} ..."
            ensure_dir("#{dest_dir}/organizations/#{name}")
            download_org(dest_dir, webui_key, name)
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

        if @error
          exit 1
        end
      end

      def ensure_dir(dir)
        if !File.exist?(dir)
          Dir.mkdir(dir)
        end
      end

      PATHS = %w(chef_repo_path cookbook_path environment_path data_bag_path role_path node_path client_path acl_path group_path container_path)
      CONFIG_VARS = %w(chef_server_url custom_http_headers node_name client_key) + PATHS
      def download_org(dest_dir, webui_key, name)
        old_config = {}
        CONFIG_VARS.each do |key|
          old_config[key] = Chef::Config[key]
        end
        begin
          # Clear out paths
          PATHS.each do |path_var|
            Chef::Config[path_var] = nil
          end
          Chef::Config.chef_repo_path = "#{dest_dir}/organizations/#{name}"

          Chef::Config.chef_server_url = "#{Chef::Config.chef_server_url}/organizations/#{name}"

          ensure_dir(Chef::Config.chef_repo_path)

          # Download the billing-admins acls as pivotal
          chef_fs_config = ::ChefFS::Config.new
          %w(/acls/groups/billing-admins.json).each do |name|
            pattern = ::ChefFS::FilePattern.new(name) 
            if ::ChefFS::FileSystem.copy_to(pattern, chef_fs_config.local_fs, chef_fs_config.chef_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) })
              @error = true
            end
          end

          # Figure out who the admin is so we can spoof him and retrieve his stuff
          rest = Chef::REST.new(Chef::Config.chef_server_url)
          admin_users = rest.get_rest('groups/admins')['users']
          org_members = rest.get_rest('users').map { |user| user['user']['username'] }
          admin_users.delete_if { |user| !org_members.include?(user) }
          Chef::Config.node_name = admin_users[0]
          Chef::Config.client_key = webui_key
          Chef::Config.custom_http_headers = (Chef::Config.custom_http_headers || {}).merge({'x-ops-request-source' => 'web'})

          # Do the download
          chef_fs_config = ::ChefFS::Config.new
          root_pattern = ::ChefFS::FilePattern.new('/')
          if ::ChefFS::FileSystem.copy_to(root_pattern, chef_fs_config.chef_fs, chef_fs_config.local_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) })
            @error = true
          end
        ensure
          CONFIG_VARS.each do |key|
            Chef::Config[key] = old_config[key]
          end
        end
      end
    end
  end
end
