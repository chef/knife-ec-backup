require 'chef/knife'

class Chef
  class Knife
    class OpcBackup < Chef::Knife
      banner "knife opc backup"

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
          user_acl_rest = Chef::REST.new(name_args[3])
        end
        # Grab users
        ensure_dir("#{dest_dir}/users")

        puts "Grabbing users ..."
        rest.get_rest('/users').each_pair do |name, url|
          File.open("#{dest_dir}/users/#{name}.json", 'w') do |file|
            file.write(rest.get_rest(url).to_json)
          end
        end

        # Download organizations
        ensure_dir("#{dest_dir}/organizations")
        rest.get_rest('/organizations').each_pair do |name, url|
          org = rest.get_rest(url)
          if org['assigned_at']
            puts "Grabbing organization #{name} ..."
            File.open("#{dest_dir}/organizations/#{name}.json", 'w') do |file|
              file.write(org.to_json)
            end
            download_org(dest_dir, webui_key, name)
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

      def download_org(dest_dir, webui_key, name)
        @old_chef_server_url = Chef::Config.chef_server_url
        @old_chef_repo_path = Chef::Config.chef_repo_path
        @old_node_name = Chef::Config.node_name
        @old_custom_http_headers = Chef::Config.custom_http_headers
        @old_client_key = Chef::Config.client_key
        begin
          Chef::Config.chef_server_url = "#{Chef::Config.chef_server_url}/organizations/#{name}"
          Chef::Config.chef_repo_path = "#{dest_dir}/organizations/#{name}"

          # Figure out who the admin is so we can spoof him and retrieve his stuff
          admin_users = rest.get_rest('groups/admins')['users']
          org_members = rest.get_rest('users').map { |user| user['user']['username'] }
          admin_users.delete_if { |user| !org_members.include?(user) }
          Chef::Config.node_name = admin_users[0]
          Chef::Config.client_key = webui_key
          Chef::Config.custom_http_headers = (Chef::Config.custom_http_headers || {}).merge({'x-ops-request-source' => 'web'})

          # Do the download
          ensure_dir(Chef::Config.chef_repo_path)
          @chef_fs_config ||= ::ChefFS::Config.new
          root_pattern = ::ChefFS::FilePattern.new('/')
          if ::ChefFS::FileSystem.copy_to(root_pattern, @chef_fs_config.chef_fs, @chef_fs_config.local_fs, nil, config, ui, proc { |entry| @chef_fs_config.format_path(entry) })
            @error = true
          end
        ensure
          Chef::Config.chef_server_url = @old_chef_server_url
          Chef::Config.chef_repo_path = @old_chef_repo_path
          Chef::Config.node_name = @old_node_name
          Chef::Config.custom_http_headers = @old_custom_http_headers
          Chef::Config.client_key = @old_client_key
        end
      end
    end
  end
end
