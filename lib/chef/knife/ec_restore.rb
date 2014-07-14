require 'chef/knife'
require 'chef/knife/ec_base'

class Chef
  class Knife
    class EcRestore < Chef::Knife

      include Knife::EcBase

      banner "knife ec restore DIRECTORY"

      option :overwrite_pivotal,
        :long => '--overwrite-pivotal',
        :boolean => true,
        :default => false,
        :description => "Whether to overwrite pivotal's key.  Once this is done, future requests will fail until you fix the private key."

      option :skip_users,
        :long => "--skip-users",
        :description => "Skip restoring users"

      deps do
        require 'chef/json_compat'
        require 'chef/chef_fs/config'
        require 'chef/chef_fs/file_system'
        require 'chef/chef_fs/file_pattern'
        # Work around bug in chef_fs
        require 'chef/chef_fs/command_line'
        require 'chef/chef_fs/file_system/acl_entry'
        require 'chef/chef_fs/data_handler/acl_data_handler'
        require 'securerandom'
        require 'chef/chef_fs/parallelizer'
        require 'chef/tsorter'
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

        # Restore users
        restore_users(dest_dir, rest) unless config[:skip_users]
        restore_user_sql(dest_dir) if config[:with_user_sql]

        # Restore organizations
        Dir.foreach("#{dest_dir}/organizations") do |name|
          next if name == '..' || name == '.' || !File.directory?("#{dest_dir}/organizations/#{name}")
          next unless (config[:org].nil? || config[:org] == name)
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
                ui.error("Cannot create invitation #{invitation['id']}")
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
          put_acl(user_acl_rest, "users/#{name}/_acl", user_acl)
        end


        if @error
          exit 1
        end
      end

      def restore_users(dest_dir, rest)
        puts "Restoring users ..."
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
      end

      def restore_user_sql(dest_dir)
        require 'chef/knife/ec_key_import'
        k = Chef::Knife::EcKeyImport.new
        k.name_args = ["#{dest_dir}/key_dump.json"]
        k.config[:skip_pivotal] = true
        k.config[:skip_ids] = false
        k.config[:sql_host] = config[:sql_host]
        k.config[:sql_port] = config[:sql_port]
        k.config[:sql_user] = config[:sql_user]
        k.config[:sql_password] = config[:sql_password]
        k.run
      end

      PATHS = %w(chef_repo_path cookbook_path environment_path data_bag_path role_path node_path client_path acl_path group_path container_path)
      def upload_org(dest_dir, webui_key, name)
        old_config = Chef::Config.save

        begin
          # Clear out paths
          PATHS.each do |path|
            Chef::Config.delete(path.to_sym)
          end

          Chef::Config.chef_repo_path = "#{dest_dir}/organizations/#{name}"
          Chef::Config.versioned_cookbooks = true

          Chef::Config.chef_server_url = "#{@server.root_url}/organizations/#{name}"

          # Upload the admins group and billing-admins acls
          puts "Restoring the org admin data"
          chef_fs_config = Chef::ChefFS::Config.new

          # Restore users w/o clients (which don't exist yet)
          ['admins', 'billing-admins'].each do |group|
            restore_group(chef_fs_config, group, :clients => false)
          end

          pattern = Chef::ChefFS::FilePattern.new('/acls/groups/billing-admins.json')
          if Chef::ChefFS::FileSystem.copy_to(pattern, chef_fs_config.local_fs, chef_fs_config.chef_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) })
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
          chef_fs_config = Chef::ChefFS::Config.new
          top_level_paths = chef_fs_config.local_fs.children.select { |entry| entry.name != 'acls' && entry.name != 'groups' }.map { |entry| entry.path }

          # Topologically sort groups for upload
          unsorted_groups = Chef::ChefFS::FileSystem.list(chef_fs_config.local_fs, Chef::ChefFS::FilePattern.new('/groups/*')).select { |entry| entry.name != 'billing-admins.json' }.map { |entry| JSON.parse(entry.read) }
          group_paths = sort_groups_for_upload(unsorted_groups).map { |group_name| "/groups/#{group_name}.json" }

          group_acl_paths = Chef::ChefFS::FileSystem.list(chef_fs_config.local_fs, Chef::ChefFS::FilePattern.new('/acls/groups/*')).select { |entry| entry.name != 'billing-admins.json' }.map { |entry| entry.path }
          acl_paths = Chef::ChefFS::FileSystem.list(chef_fs_config.local_fs, Chef::ChefFS::FilePattern.new('/acls/*')).select { |entry| entry.name != 'groups' }.map { |entry| entry.path }

          (top_level_paths + group_paths + group_acl_paths + acl_paths).each do |path|
            Chef::ChefFS::FileSystem.copy_to(Chef::ChefFS::FilePattern.new(path), chef_fs_config.local_fs, chef_fs_config.chef_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) })
          end
          # restore clients to groups, using the pivotal key again
          Chef::Config[:node_name] = old_config[:node_name]
          Chef::Config[:client_key] = old_config[:client_key]
          Chef::Config.custom_http_headers = {}
          ['admins', 'billing-admins'].each do |group|
            restore_group(Chef::ChefFS::Config.new, group)
          end
         ensure
          Chef::Config.restore(old_config)
        end
      end

      # Takes an array of group objects
      # and topologically sorts them
      def sort_groups_for_upload(groups)
        Chef::Tsorter.new(group_array_to_sortable_hash(groups)).tsort
      end

      def group_array_to_sortable_hash(groups)
        ret = {}
        groups.each do |group|
          name = group["name"]
          ret[name] = if group.key?("groups")
                        group["groups"]
                      else
                        []
                      end
        end
        ret
      end

      def restore_group(chef_fs_config, group_name, includes = {:users => true, :clients => true})
        includes[:users] = true unless includes.key? :users
        includes[:clients] = true unless includes.key? :clients

        group = Chef::ChefFS::FileSystem.resolve_path(
          chef_fs_config.chef_fs,
          "/groups/#{group_name}.json"
        )

        members_json = Chef::ChefFS::FileSystem.resolve_path(
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
        Chef::ChefFS::Parallelizer.parallelize(entries, options, &block)
      end

      def put_acl(rest, url, acls)
        old_acls = rest.get_rest(url)
        old_acls = Chef::ChefFS::DataHandler::AclDataHandler.new.normalize(old_acls, nil)
        acls = Chef::ChefFS::DataHandler::AclDataHandler.new.normalize(acls, nil)
        if acls != old_acls
          Chef::ChefFS::FileSystem::AclEntry::PERMISSIONS.each do |permission|
            rest.put_rest("#{url}/#{permission}", { permission => acls[permission] })
          end
        end
      end
    end
  end
end
