require 'chef/knife'

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
      end

      def configure_chef
        super
        Chef::Config[:concurrency] = config[:concurrency].to_i if config[:concurrency]
        Chef::ChefFS::Parallelizer.threads = (Chef::Config[:concurrency] || 10) - 1
      end

      def run
        #Check for destination directory argument
        if name_args.length <= 0
          ui.error("Must specify backup directory as an argument.")
          exit 1
        end
        dest_dir = name_args[0]


        #Check for pivotal user and key
        node_name = Chef::Config.node_name
        client_key = Chef::Config.client_key
        if node_name != "pivotal"
          if !File.exist?("/etc/opscode/pivotal.pem")
            ui.error("Username not configured as pivotal and /etc/opscode/pivotal.pem does not exist.  It is recommended that you run this plugin from your Chef server.")
            exit 1
          end
          Chef::Config.node_name = 'pivotal'
          Chef::Config.client_key = '/etc/opscode/pivotal.pem'
        end

        #Check for WebUI Key
        if !File.exist?(config[:webui_key])
          ui.error("Webui Key (#{config[:webui_key]}) does not exist.")
          exit 1
        end

        @server = if Chef::Config.chef_server_root.nil?
                    ui.warn("chef_server_root not found in knife configuration; using chef_server_url")
                    Chef::Server.from_chef_server_url(Chef::Config.chef_server_url)
                  else
                    Chef::Server.new(Chef::Config.chef_server_root)
                  end

        rest = Chef::REST.new(@server.root_url)
        user_acl_rest = if config[:skip_version]
                          rest
                        elsif @server.supports_user_acls?
                          rest
                        elsif @server.direct_account_access?
                          Chef::REST.new("http://127.0.0.1:9465")
                        end

        # Grab users
        puts "Grabbing users ..."
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

        if config[:with_user_sql]
          require 'chef/knife/ec_key_export'
          Chef::Knife::EcKeyExport.deps
          k = Chef::Knife::EcKeyExport.new
          k.name_args = ["#{dest_dir}/key_dump.json"]
          k.config[:sql_host] = config[:sql_host]
          k.config[:sql_port] = config[:sql_port]
          k.config[:sql_user] = config[:sql_user]
          k.config[:sql_password] = config[:sql_password]
          k.run
        end

        # Download organizations
        ensure_dir("#{dest_dir}/organizations")
        rest.get_rest('/organizations').each_pair do |name, url|
          do_org = (config[:org].nil? || config[:org] == name)
          org = rest.get_rest(url)
          if org['assigned_at'] and do_org
            puts "Grabbing organization #{name} ..."
            ensure_dir("#{dest_dir}/organizations/#{name}")
            download_org(dest_dir, config[:webui_key], name)
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
      def download_org(dest_dir, webui_key, name)
        old_config = Chef::Config.save

        begin
          # Clear out paths
          PATHS.each do |path|
            Chef::Config.delete(path.to_sym)
          end
          Chef::Config.chef_repo_path = "#{dest_dir}/organizations/#{name}"
          Chef::Config.versioned_cookbooks = true

          Chef::Config.chef_server_url = "#{@server.root_url}/organizations/#{name}"

          ensure_dir(Chef::Config.chef_repo_path)

          # Download the billing-admins ACL and group as pivotal
          chef_fs_config = Chef::ChefFS::Config.new
          pattern = Chef::ChefFS::FilePattern.new('/acls/groups/billing-admins.json')
          if Chef::ChefFS::FileSystem.copy_to(pattern, chef_fs_config.chef_fs, chef_fs_config.local_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) })
            @error = true
          end
          pattern = Chef::ChefFS::FilePattern.new('/groups/billing-admins.json')
          if Chef::ChefFS::FileSystem.copy_to(pattern, chef_fs_config.chef_fs, chef_fs_config.local_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) })
            @error = true
          end
          pattern = Chef::ChefFS::FilePattern.new('/groups/admins.json')
          if Chef::ChefFS::FileSystem.copy_to(pattern, chef_fs_config.chef_fs, chef_fs_config.local_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) })
            @error = true
          end

          # Figure out who the admin is so we can spoof him and retrieve his stuff
          rest = Chef::REST.new(Chef::Config.chef_server_url)
          admin_users = rest.get_rest('groups/admins')['users']
          org_members = rest.get_rest('users').map { |user| user['user']['username'] }
          admin_users.delete_if { |user| !org_members.include?(user) }
          Chef::Config.node_name = admin_users[0]
          Chef::Config.client_key = webui_key
          Chef::Config.custom_http_headers = (Chef::Config.custom_http_headers || {}).merge({'x-ops-request-source' => 'web'})

          # Download the entire org skipping the billing admins group ACL and the group itself
          chef_fs_config = Chef::ChefFS::Config.new
          top_level_paths = chef_fs_config.chef_fs.children.select { |entry| entry.name != 'acls' && entry.name != 'groups' }.map { |entry| entry.path }
          acl_paths = Chef::ChefFS::FileSystem.list(chef_fs_config.chef_fs, Chef::ChefFS::FilePattern.new('/acls/*')).select { |entry| entry.name != 'groups' }.map { |entry| entry.path }
          group_acl_paths = Chef::ChefFS::FileSystem.list(chef_fs_config.chef_fs, Chef::ChefFS::FilePattern.new('/acls/groups/*')).select { |entry| entry.name != 'billing-admins.json' }.map { |entry| entry.path }
          group_paths = Chef::ChefFS::FileSystem.list(chef_fs_config.chef_fs, Chef::ChefFS::FilePattern.new('/groups/*')).select { |entry| entry.name != 'billing-admins.json' }.map { |entry| entry.path }
          (top_level_paths + group_acl_paths + acl_paths + group_paths).each do |path|
            Chef::ChefFS::FileSystem.copy_to(Chef::ChefFS::FilePattern.new(path), chef_fs_config.chef_fs, chef_fs_config.local_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) })
          end

        ensure
          Chef::Config.restore(old_config)
        end
      end
    end
  end
end
