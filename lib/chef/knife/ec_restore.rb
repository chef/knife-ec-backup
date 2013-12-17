require 'chef/knife'

class Chef
  class Knife
    class EcRestore < Chef::Knife
      banner "knife ec restore"

      option :concurrency,
        :long => '--concurrency THREADS',
        :description => 'Maximum number of simultaneous requests to send (default: 10)'

      option :overwrite_pivotal,
        :long => '--overwrite-pivotal',
        :boolean => true,
        :default => false,
        :description => "Whether to overwrite pivotal's key.  Once this is done, future requests will fail until you fix the private key."

      option :skip_useracl,
        :long => '--skip-useracl',
        :boolean => true,
        :default => false,
        :description => "Whether to skip restoring User ACLs.  This is required for EC 11.0.2 and lower"


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

      def configure_chef
        super
        Chef::Config[:concurrency] = config[:concurrency].to_i if config[:concurrency]
        ::ChefFS::Parallelizer.threads = (Chef::Config[:concurrency] || 10) - 1
      end

      def run
        #Check arguments
        if name_args.length <= 1
          ui.error("Must specify backup directory and WebUI key as arguments.")
          exit 1
        end

        dest_dir = name_args[0]
        webui_key = name_args[1]
        rest = Chef::REST.new(Chef::Config.chef_server_root)
        if name_args.length >= 3
          user_acl_rest = Chef::REST.new(name_args[2])
        else
          user_acl_rest = rest
        end

        # Restore users
        puts "Restoring users ..."
        Dir.foreach("#{dest_dir}/users") do |filename|
          next if filename !~ /(.+)\.json/
          name = $1
          if name == 'pivotal' && !config[:overwrite_pivotal]
            ui.warn("Skipping pivotal update.  To overwrite pivotal, pass --overwrite-pivotal.  Once pivotal is updated, you will need to modify #{Chef::Config.client_key} to be the corresponding private key.")
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
          parallelize(invitations) do |invitation|
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
          parallelize(members) do |member|
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
            ui.warn("Skipping user ACL update for #{name}. To update this ACL, remove --skip-useracl.")
            next
          end
          if name == 'pivotal' && !config[:overwrite_pivotal]
            ui.warn("Skipping pivotal update.  To overwrite pivotal, pass --overwrite-pivotal.  Once pivotal is updated, you will need to modify #{Chef::Config.client_key} to be the corresponding private key.")
            next
          end

          # Update user acl
          user_acl = JSONCompat.from_json(IO.read("#{dest_dir}/user_acls/#{name}.json"))
          put_acl(user_acl_rest, "users/#{name}/_acl", user_acl)          
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
          chef_fs_config = ::ChefFS::Config.new
          %w(/groups/admins.json /groups/billing-admins.json /acls/groups/billing-admins.json).each do |name|
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

          # Do the upload.
          chef_fs_config = ::ChefFS::Config.new
          # groups and acls come last.
          children = chef_fs_config.chef_fs.children.map { |child| child.name }
          children.delete('acls')
          children.delete('groups')
          parallelize(children) do |child_name|
            pattern = ::ChefFS::FilePattern.new("/#{child_name}") 
            if ::ChefFS::FileSystem.copy_to(pattern, chef_fs_config.local_fs, chef_fs_config.chef_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) })
              @error = true
            end
          end
          pattern = ::ChefFS::FilePattern.new("/groups") 
          if ::ChefFS::FileSystem.copy_to(pattern, chef_fs_config.local_fs, chef_fs_config.chef_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) })
            @error = true
          end
          pattern = ::ChefFS::FilePattern.new("/acls") 
          if ::ChefFS::FileSystem.copy_to(pattern, chef_fs_config.local_fs, chef_fs_config.chef_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) })
            @error = true
          end
        ensure
          CONFIG_VARS.each do |key|
            Chef::Config[key.to_sym] = old_config[key]
          end
        end
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
