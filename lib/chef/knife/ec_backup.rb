require 'chef/knife'

class Chef
  class Knife
    class EcBackup < Chef::Knife
      banner "knife ec backup DIRECTORY"

      option :concurrency,
        :long => '--concurrency THREADS',
        :description => 'Maximum number of simultaneous requests to send (default: 10)'

      option :webui_key,
        :long => '--webui-key KEYPATH',
        :description => 'Used to set the path to the WebUI Key (default: /etc/opscode/webui_priv.pem)'

      option :skip_useracl,
        :long => '--skip-useracl',
        :boolean => true,
        :default => false,
        :description => "Whether to skip downloading User ACLs.  This is required for EC 11.0.0 and lower"

      option :skip_version,
        :long => '--skip-version-check',
        :boolean => true,
        :default => false,
        :description => "Whether to skip checking the Chef Server version.  This will also skip any auto-configured options"

      option :org,
        :long => '--only-org ORGNAME',
        :description => "Only back up objects in the named organization (default: all orgs)"

      deps do
        require 'chef/chef_fs/config'
        require 'chef/chef_fs/file_system'
        require 'chef/chef_fs/file_pattern'
        require 'chef/chef_fs/parallelizer'
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
        if config[:webui_key] == nil
          if !File.exist?("/etc/opscode/webui_priv.pem")
            ui.error("WebUI not specified and /etc/opscode/webui_priv.pem does not exist.  It is recommended that you run this plugin from your Chef server.")
            exit 1
          end
          ui.warn("WebUI not specified. Using /etc/opscode/webui_priv.pem")
          webui_key = '/etc/opscode/webui_priv.pem'
        else
          webui_key = config[:webui_key]
        end

        #Set the server root
        server_root = Chef::Config.chef_server_root
        if server_root == nil
          server_root = Chef::Config.chef_server_url.gsub(/\/organizations\/+[^\/]+\/*$/, '')
          ui.warn("chef_server_root not found in knife configuration. Setting root to: #{server_root}")
          Chef::Config.chef_server_root = server_root
        end

        rest = Chef::REST.new(Chef::Config.chef_server_root)
       
        if config[:skip_version] && config[:skip_useracl]
          ui.warn("Skipping the Chef Server version check.  This will also skip any auto-configured options")
          user_acl_rest = nil
        elsif config[:skip_version] && !config[:skip_useracl]
          ui.warn("Skipping the Chef Server version check.  This will also skip any auto-configured options")
          user_acl_rest = rest
        else # Grab Chef Server version number so that we can auto set options
          uri = URI.parse("#{Chef::Config.chef_server_root}/version")
          server_version = open(uri, {ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE}).each_line.first.split(' ').last
          server_version_parts = server_version.split('.')

          if server_version_parts.count == 3
            puts "Detected Enterprise Chef Server version: #{server_version}"

            # All versions of Chef Server below 11.0.1 are missing the GET User ACL helper in nginx
            if server_version_parts[0].to_i < 11 || (server_version_parts[0].to_i == 11 && server_version_parts[1].to_i == 0 && server_version_parts[0].to_i < 1)
              #Check to see if Opscode-Account can be directly from the local machine  
              begin
                user_acl_rest.get('users')
                ui.warn("Your version of Enterprise Chef Server does not support the downloading of User ACLs.  Using local connection to backup")
                user_acl_rest = Chef::REST.new("http://127.0.0.1:9465")
              rescue
                ui.warn("Your version of Enterprise Chef Server does not support the downloading of User ACLs.  Setting skip-useracl to TRUE")
                config[:skip_useracl] = true
                user_acl_rest = nil
              end
            else
              user_acl_rest = rest
            end

          else
            ui.warn("Unable to detect Chef Server version.")
          end
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

        # Download organizations
        ensure_dir("#{dest_dir}/organizations")
        rest.get_rest('/organizations').each_pair do |name, url|
          do_org = (config[:org].nil? || config[:org] == name)
          org = rest.get_rest(url)
          if org['assigned_at'] and do_org
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
      def download_org(dest_dir, webui_key, name)
        old_config = Chef::Config.save

        # Clear out paths
        PATHS.each do |path|
          Chef::Config.delete(path.to_sym)
        end

        begin
          Chef::Config.chef_repo_path = "#{dest_dir}/organizations/#{name}"
          Chef::Config.versioned_cookbooks = true

          Chef::Config.chef_server_url = "#{Chef::Config.chef_server_root}/organizations/#{name}"

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
