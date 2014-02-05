require 'chef/knife'
require 'chef/knife/ec_base'

class Chef
  class Knife
    class EcRestore < Chef::Knife
      banner "knife ec restore"

      include Knife::EcBase

      option :overwrite_pivotal,
        :long => '--overwrite-pivotal',
        :boolean => true,
        :default => false,
        :description => "Whether to overwrite pivotal's key.  Once this is done, future requests will fail until you fix the private key."

      deps do
        require 'chef/json_compat'
        require 'chef_fs/config'
        require 'chef_fs/file_system'
        require 'chef_fs/file_pattern'
        require 'chef_fs/file_system/acl_entry'
        require 'chef_fs/data_handler/acl_data_handler'
        require 'securerandom'
        require 'chef_fs/parallelizer'
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
          node_name = 'pivotal'
          client_key = '/etc/opscode/pivotal.pem'
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

            # All versions of Chef Server below 11.0.X are unable to update user acls
            if server_version_parts[0].to_i < 11 || (server_version_parts[0].to_i == 11 && server_version_parts[1].to_i == 0)
              ui.warn("Your version of Enterprise Chef Server does not support the updating of User ACLs.  Setting skip-useracl to TRUE")
              config[:skip_useracl] = true
              user_acl_rest = nil
            else
              user_acl_rest = rest 
            end             
          else
            ui.warn("Unable to detect Chef Server version.")
          end
        end

        # Restore users
        puts "Restoring users ..."

        rest = Chef::REST.new(Chef::Config.chef_server_root)

        Dir.foreach("#{dest_dir}/users") do |filename|
          next if filename !~ /(.+)\.json/
          name = $1
          if name == 'pivotal' && !config[:overwrite_pivotal]
            ui.warn("Skipping pivotal update.  To overwrite pivotal, pass --overwrite-pivotal.")
            next
          end

          # Update user object
          user = JSONCompat.from_json(IO.read("#{dest_dir}/users/#{name}.json"))
          begin
            # Supply password for new user
            user_with_password = user.dup
            user_with_password['password'] = SecureRandom.hex
            rest.post_rest('users', user_with_password)
          rescue Net::HTTPServerException => e
            if e.response.code == "409"
              rest.put_rest("users/#{name}", user)
            else
              raise
            end
          end

        end

        # Restore organizations
        Dir.foreach("#{dest_dir}/organizations") do |name|
          next if name == '..' || name == '.' || !File.directory?("#{dest_dir}/organizations/#{name}")
          puts "Restoring org #{name} ..."

          # Create organization
          org = JSONCompat.from_json(IO.read("#{dest_dir}/organizations/#{name}/org.json"))
          begin
            rest.post_rest('organizations', org)
          rescue Net::HTTPServerException => e
            if e.response.code == "409"
              rest.put_rest("organizations/#{name}", org)
            else
              raise
            end
          end

          # Restore open invitations
          invitations = JSONCompat.from_json(IO.read("#{dest_dir}/organizations/#{name}/invitations.json"))
          invitations.each do |invitation|
            begin
              rest.post_rest("organizations/#{name}/association_requests", { 'user' => invitation['username'] })
            rescue Net::HTTPServerException => e
              if e.response.code != "409"
                raise
              end
            end
          end

          # Repopulate org members
          members = JSONCompat.from_json(IO.read("#{dest_dir}/organizations/#{name}/members.json"))
          members.each do |member|
            username = member['user']['username']
            begin
              response = rest.post_rest("organizations/#{name}/association_requests", { 'user' => username })
              association_id = response["uri"].split("/").last
              rest.put_rest("users/#{username}/association_requests/#{association_id}", { 'response' => 'accept' })
            rescue Net::HTTPServerException => e
              if e.response.code != "409"
                raise
              end
            end
          end

          # Upload org data
          upload_org(dest_dir, webui_key, name)
        end

        # Restore user ACLs
        puts "Restoring user ACLs ..."
        Dir.foreach("#{dest_dir}/users") do |filename|
          next if filename !~ /(.+)\.json/
          name = $1
          if config[:skip_useracl]
            ui.warn("Skipping user ACL update for #{name}. To update this ACL, remove --skip-useracl or upgrade your Enterprise Chef Server.")
            next
          end
          if name == 'pivotal' && !config[:overwrite_pivotal]
            ui.warn("Skipping pivotal update.  To overwrite pivotal, pass --overwrite-pivotal.")
            next
          end

          # Update user acl
          user_acl = JSONCompat.from_json(IO.read("#{dest_dir}/user_acls/#{name}.json"))
          put_acl(rest, "users/#{name}/_acl", user_acl)          
        end


        if @error
          exit 1
        end
      end

      PATHS = %w(chef_repo_path cookbook_path environment_path data_bag_path role_path node_path client_path acl_path group_path container_path)
      CONFIG_VARS = %w(chef_server_url chef_server_root custom_http_headers node_name client_key versioned_cookbooks) + PATHS
      def upload_org(dest_dir, webui_key, name)
        old_config = {}
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

          # Upload the admins group and billing-admins acls
          puts "Restoring the org admin data"
          chef_fs_config = ::ChefFS::Config.new

          # Restore users w/o clients (which don't exist yet)
          ['admins', 'billing-admins'].each do |group|
            restore_group(chef_fs_config, group, :clients => false)
          end

          pattern = ::ChefFS::FilePattern.new('/acls/groups/billing-admins.json')
          if ::ChefFS::FileSystem.copy_to(pattern, chef_fs_config.local_fs, chef_fs_config.chef_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) })
            @error = true
          end

          # Figure out who the admin is so we can spoof him and retrieve his stuff
          rest = Chef::REST.new(Chef::Config.chef_server_url)
          org_admins = rest.get_rest('groups/admins')['users']
          org_members = rest.get_rest('users').map { |user| user['user']['username'] }
          org_admins.delete_if { |user| !org_members.include?(user) || user == 'pivotal' }
          if org_admins[0] != nil
            # Using an org admin already on the destination server
            Chef::Config.node_name = org_admins[0]
            Chef::Config.client_key = webui_key
          else
            # No suitable org admins found, defaulting to pivotal
            ui.warn("No suitable Organizational Admins found.  Defaulting to pivotal for org creation")
          end
          Chef::Config.custom_http_headers = (Chef::Config.custom_http_headers || {}).merge({'x-ops-request-source' => 'web'})

          # Restore the entire org skipping the admin data and restoring groups and acls last
          puts "Restoring the rest of the org"
          chef_fs_config = ::ChefFS::Config.new
          top_level_paths = chef_fs_config.local_fs.children.select { |entry| entry.name != 'acls' && entry.name != 'groups' }.map { |entry| entry.path }
          acl_paths = ::ChefFS::FileSystem.list(chef_fs_config.local_fs, ::ChefFS::FilePattern.new('/acls/*')).select { |entry| entry.name != 'groups' }.map { |entry| entry.path }
          group_acl_paths = ::ChefFS::FileSystem.list(chef_fs_config.local_fs, ::ChefFS::FilePattern.new('/acls/groups/*')).select { |entry| entry.name != 'billing-admins.json' }.map { |entry| entry.path }
          group_paths = ::ChefFS::FileSystem.list(chef_fs_config.local_fs, ::ChefFS::FilePattern.new('/groups/*')).select { |entry| entry.name != 'billing-admins.json' }.map { |entry| entry.path }
          (top_level_paths + group_paths + group_acl_paths + acl_paths).each do |path|
            ::ChefFS::FileSystem.copy_to(::ChefFS::FilePattern.new(path), chef_fs_config.local_fs, chef_fs_config.chef_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) })
          end
          # restore clients to groups, using the pivotal key again
          Chef::Config[:node_name] = old_config['node_name']
          Chef::Config[:client_key] = old_config['client_key'] 
          Chef::Config.custom_http_headers = {}
          ['admins', 'billing-admins'].each do |group|
            restore_group(::ChefFS::Config.new, group, :users => false)
          end
         ensure
          CONFIG_VARS.each do |key|
            Chef::Config[key.to_sym] = old_config[key]
          end
        end
      end

      def restore_group(chef_fs_config, group_name, includes = {:users => true, :clients => true})
        includes[:users] = true unless includes.key? :users
        includes[:clients] = true unless includes.key? :clients
      
        group = ::ChefFS::FileSystem.resolve_path(
          chef_fs_config.chef_fs,
          "/groups/#{group_name}.json"
        )

        members_json = ::ChefFS::FileSystem.resolve_path(
          chef_fs_config.local_fs,
          "/groups/#{group_name}.json"
        ).read

        members = JSON.parse(members_json).select do |member|
          if includes[:users] and includes[:clients]
            member
          elsif includes[:users]
            member == 'users'
          elsif includes[:clients]
            member == 'clients'
          end
        end
        
        group.write(members.to_json)
      end

      def parallelize(entries, options = {}, &block)
        ::ChefFS::Parallelizer.parallelize(entries, options, &block)
      end

      def put_acl(rest, url, acls)
        old_acls = rest.get_rest(url)
        old_acls = ::ChefFS::DataHandler::AclDataHandler.new.normalize(old_acls, nil)
        acls = ::ChefFS::DataHandler::AclDataHandler.new.normalize(acls, nil)
        if acls != old_acls
          ::ChefFS::FileSystem::AclEntry::PERMISSIONS.each do |permission|
            rest.put_rest("#{url}/#{permission}", { permission => acls[permission] })
          end
        end
      end
    end
  end
end
