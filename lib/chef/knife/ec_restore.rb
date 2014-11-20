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

      def run
        set_dest_dir_from_args!
        set_client_config!
        ensure_webui_key_exists!

        restore_users unless config[:skip_users]
        restore_user_sql if config[:with_user_sql]

        for_each_organization do |orgname|
          create_organization(orgname)
          restore_open_invitations(orgname)
          add_users_to_org(orgname)
          upload_org_data(orgname)
        end

        if config[:skip_useracl]
          ui.warn("Skipping user ACL update. To update user ACLs, remove --skip-useracl or upgrade your Enterprise Chef Server.")
        else
          restore_user_acls
        end
      end

      def create_organization(orgname)
        org = JSONCompat.from_json(IO.read("#{dest_dir}/organizations/#{orgname}/org.json"))
        rest.post_rest('organizations', org)
      rescue Net::HTTPServerException => e
        if e.response.code == "409"
          rest.put_rest("organizations/#{orgname}", org)
        else
          raise
        end
      end

      def restore_open_invitations(orgname)
        invitations = JSONCompat.from_json(IO.read("#{dest_dir}/organizations/#{orgname}/invitations.json"))
        invitations.each do |invitation|
          begin
            rest.post_rest("organizations/#{orgname}/association_requests", { 'user' => invitation['username'] })
          rescue Net::HTTPServerException => e
            if e.response.code != "409"
              ui.error("Cannot create invitation #{invitation['id']}")
            end
          end
        end
      end

      def add_users_to_org(orgname)
        members = JSONCompat.from_json(IO.read("#{dest_dir}/organizations/#{orgname}/members.json"))
        members.each do |member|
          username = member['user']['username']
          begin
            response = rest.post_rest("organizations/#{orgname}/association_requests", { 'user' => username })
            association_id = response["uri"].split("/").last
            rest.put_rest("users/#{username}/association_requests/#{association_id}", { 'response' => 'accept' })
          rescue Net::HTTPServerException => e
            if e.response.code != "409"
              raise
            end
          end
        end
      end

      def restore_user_acls
        puts "Restoring user ACLs ..."
        Dir.foreach("#{dest_dir}/users") do |filename|
          next if filename !~ /(.+)\.json/
          name = $1

          if name == 'pivotal' && !config[:overwrite_pivotal]
            ui.warn("Skipping pivotal update.  To overwrite pivotal, pass --overwrite-pivotal.")
            next
          end

          user_acl = JSONCompat.from_json(IO.read("#{dest_dir}/user_acls/#{name}.json"))
          put_acl(user_acl_rest, "users/#{name}/_acl", user_acl)
        end
      end

      def for_each_organization(&block)
        Dir.foreach("#{dest_dir}/organizations") do |name|
          next if name == '..' || name == '.' || !File.directory?("#{dest_dir}/organizations/#{name}")
          next unless (config[:org].nil? || config[:org] == name)
          yield name
        end
      end

      def restore_users
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

      def restore_user_sql
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
      def upload_org_data(name)
        old_config = Chef::Config.save

        begin
          # Clear out paths
          PATHS.each do |path|
            Chef::Config.delete(path.to_sym)
          end

          Chef::Config.chef_repo_path = "#{dest_dir}/organizations/#{name}"
          Chef::Config.versioned_cookbooks = true
          Chef::Config.chef_server_url = "#{server.root_url}/organizations/#{name}"

          # Upload the admins group and billing-admins acls
          puts "Restoring the org admin data"
          chef_fs_config = Chef::ChefFS::Config.new

          # Handle Admins and Billing Admins seperately
          #
          # admins: We need to upload admins first so that we
          # can upload all of the other objects as a user in the org
          # rather than as pivotal.  Because the clients, and groups, don't
          # exist yet, we first upload the group with only the users.
          #
          # billing-admins: The default permissions on the
          # billing-admin group only give update permissions to
          # pivotal and members of the billing-admins group. Since we
          # can't unsure that the admin we choose for uploading will
          # be in the billing admins group, we have to upload this
          # group as pivotal.  Thus, we upload its users and ACL here,
          # and then update it again once all of the clients and
          # groups are uploaded.
          #
          ['admins', 'billing-admins'].each do |group|
            restore_group(chef_fs_config, group, :clients => false)
          end

          pattern = Chef::ChefFS::FilePattern.new('/acls/groups/billing-admins.json')
          Chef::ChefFS::FileSystem.copy_to(pattern, chef_fs_config.local_fs,
                                           chef_fs_config.chef_fs, nil, config, ui,
                                           proc { |entry| chef_fs_config.format_path(entry)})

          Chef::Config.node_name = org_admin

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

          # restore clients to groups, using the pivotal user again
          Chef::Config[:node_name] = 'pivotal'
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
