require 'chef/knife'

class Chef
  class Knife
    class EcRestore < Chef::Knife
      banner "knife ec restore"

      deps do
        require 'chef/json_compat'
        require 'chef_fs/config'
        require 'chef_fs/file_system'
        require 'chef_fs/file_pattern'
        require 'chef_fs/file_system/acl_entry'
        require 'chef_fs/data_handler/acl_data_handler'
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

        # Restore users
        puts "Restoring users ..."
        Dir.foreach("#{dest_dir}/users") do |filename|
          next if filename !~ /(.+)\.json/
          name = $1
          user = JSONCompat.from_json(IO.read("#{dest_dir}/users/#{name}.json"))
          begin
            rest.post_rest('users', user)
          rescue Net::HTTPServerException => e
            if e.response.code == "409"
              rest.put_rest("users/#{name}", user)
            else
              raise
            end
          end
          user_acl = JSONCompat.from_json(IO.read("#{dest_dir}/user_acls/#{name}.json"))
          put_acl(user_acl_rest, "users/#{name}/_acl", user_acl)
        end

        # Restore organizations
        Dir.foreach("#{dest_dir}/organizations") do |filename|
          next if filename !~ /(.+)\.json/
          name = $1
          puts "Restoring org #{name} ..."
          org = JSONCompat.from_json(IO.read("#{dest_dir}/organizations/#{name}.json"))
          begin
            rest.post_rest('organizations', org)
          rescue Net::HTTPServerException => e
            if e.response.code == "409"
              rest.put_rest("organizations/#{name}", org)
            else
              raise
            end
          end
          upload_org(dest_dir, webui_key, name)
        end

        if @error
          exit 1
        end
      end

      PATHS = %w(chef_repo_path cookbook_path environment_path data_bag_path role_path node_path client_path acl_path group_path container_path)
      CONFIG_VARS = %w(chef_server_url custom_http_headers node_name client_key) + PATHS
      def upload_org(dest_dir, webui_key, name)
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

          # Figure out who the admin is so we can spoof him and retrieve his stuff
          rest = Chef::REST.new(Chef::Config.chef_server_url)
          admin_users = rest.get_rest('groups/admins')['users']
          org_members = rest.get_rest('users').map { |user| user['user']['username'] }
          admin_users.delete_if { |user| !org_members.include?(user) }
          Chef::Config.node_name = admin_users[0]
          Chef::Config.client_key = webui_key
          Chef::Config.custom_http_headers = (Chef::Config.custom_http_headers || {}).merge({'x-ops-request-source' => 'web'})

          # Do the upload
          chef_fs_config ||= ::ChefFS::Config.new
          root_pattern = ::ChefFS::FilePattern.new('/')
          if ::ChefFS::FileSystem.copy_to(root_pattern, chef_fs_config.local_fs, chef_fs_config.chef_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) })
            @error = true
          end
        ensure
          CONFIG_VARS.each do |key|
            Chef::Config[key] = old_config[key]
          end
        end
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
