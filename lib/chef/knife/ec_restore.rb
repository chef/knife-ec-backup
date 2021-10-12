require 'chef/knife'
require_relative 'ec_base'

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

      option :skip_ids,
        :long => "--[no-]skip-user-ids",
        :default => true,
        :boolean => true,
        :description => "Reuses user ids from the restore destination when updating existing users to avoid database conflicts."

      deps do
        require 'chef/json_compat'
        require 'chef/chef_fs/config'
        require 'chef/chef_fs/file_system'
        require 'chef/chef_fs/file_pattern'
        # Work around bug in chef_fs
        require 'chef/chef_fs/command_line'
        require 'chef/chef_fs/data_handler/acl_data_handler'
        require 'securerandom' unless defined?(SecureRandom)
        begin
          require 'chef/chef_fs/parallelizer'
        rescue LoadError
          require 'chef-utils/parallel_map' unless defined?(ChefUtils::ParallelMap)
        end
        require_relative '../tsorter'
        require_relative '../server'
      end

      def run
        set_dest_dir_from_args!
        set_client_config!
        ensure_webui_key_exists!
        set_skip_user_acl!

        warn_on_incorrect_clients_group(dest_dir, "restore")

        restore_users unless config[:skip_users]
        restore_user_sql if config[:with_user_sql]

        for_each_organization do |orgname|
          ui.msg "Restoring organization[#{orgname}]"
          create_organization(orgname)
          restore_open_invitations(orgname)
          add_users_to_org(orgname)
          upload_org_data(orgname)
        end

        restore_key_sql if config[:with_key_sql]

        if config[:skip_useracl]
          ui.warn("Skipping user ACL update. To update user ACLs, remove --skip-useracl or upgrade your Enterprise Chef Server.")
        else
          restore_user_acls
        end

        completion_banner
      end

      def create_organization(orgname)
        org = JSONCompat.from_json(File.read("#{dest_dir}/organizations/#{orgname}/org.json"))
        rest.post('organizations', org)
      rescue Net::HTTPServerException => ex
        if ex.response.code == "409"
          rest.put("organizations/#{orgname}", org)
        else
          knife_ec_error_handler.add(ex)
        end
      end

      def restore_open_invitations(orgname)
        invitations = JSONCompat.from_json(File.read("#{dest_dir}/organizations/#{orgname}/invitations.json"))
        invitations.each do |invitation|
          begin
            rest.post("organizations/#{orgname}/association_requests", { 'user' => invitation['username'] })
          rescue Net::HTTPServerException => ex
            if ex.response.code != "409"
              ui.error("Cannot create invitation #{invitation['id']}")
              knife_ec_error_handler.add(ex)
            end
          end
        end
      end

      def add_users_to_org(orgname)
        members = JSONCompat.from_json(File.read("#{dest_dir}/organizations/#{orgname}/members.json"))
        members.each do |member|
          username = member['user']['username']
          begin
            response = rest.post("organizations/#{orgname}/association_requests", { 'user' => username })
            association_id = response["uri"].split("/").last
            rest.put("users/#{username}/association_requests/#{association_id}", { 'response' => 'accept' })
          rescue Net::HTTPServerException => ex
            knife_ec_error_handler.add(ex) if ex.response.code != "409"
          end
        end
      end

      def restore_user_acls
        ui.msg "Restoring user ACLs"
        for_each_user do |name|
          user_acl = JSONCompat.from_json(File.read("#{dest_dir}/user_acls/#{name}.json"))
          put_acl(user_acl_rest, "users/#{name}/_acl", user_acl)
        end
      end

      def for_each_user
        Dir.foreach("#{dest_dir}/users") do |filename|
          next if filename !~ /(.+)\.json/
          name = $1
          if name == 'pivotal' && !config[:overwrite_pivotal]
            ui.warn("Skipping pivotal user.  To overwrite pivotal, pass --overwrite-pivotal.")
            next
          end
          yield name
        end
      end

      def for_each_organization
        Dir.foreach("#{dest_dir}/organizations") do |name|
          next if name == '..' || name == '.' || !File.directory?("#{dest_dir}/organizations/#{name}")
          next unless (config[:org].nil? || config[:org] == name)
          yield name
        end
      end

      def restore_users
        ui.msg "Restoring users"
        for_each_user do |name|
          user = JSONCompat.from_json(File.read("#{dest_dir}/users/#{name}.json"))
          begin
            # Supply password for new user
            user_with_password = user.dup
            user_with_password['password'] = SecureRandom.hex
            rest.post('users', user_with_password)
          rescue Net::HTTPServerException => ex
            if ex.response.code == "409"
              rest.put("users/#{name}", user)
              next
            end
            knife_ec_error_handler.add(ex)
          end
        end
        purge_users_on_restore
      end

      def users_for_purge
        purge_list = remote_user_list - local_user_list
        # failsafe - don't delete pivotal
        purge_list -= ['pivotal']
        purge_list.each do |user|
          yield user
        end
      end

      def purge_users_on_restore
        return unless config[:purge]
        users_for_purge do |user|
          ui.msg "Deleting user #{user} from remote (purge is on)"
          begin
            rest.delete("/users/#{user}")
          rescue Net::HTTPServerException => e
            ui.warn "Failed deleting user #{user} from remote #{e}"
          end
        end
      end

      def ec_key_import
        @ec_key_import ||= begin
                             require_relative 'ec_key_import'
                             k = Chef::Knife::EcKeyImport.new
                             k.name_args = ["#{dest_dir}/key_dump.json", "#{dest_dir}/key_table_dump.json"]
                             k.config[:skip_pivotal] = true
                             k.config[:skip_ids] = config[:skip_ids]
                             k.config[:sql_host] = config[:sql_host]
                             k.config[:sql_port] = config[:sql_port]
                             k.config[:sql_db] = config[:sql_db]
                             k.config[:sql_user] = config[:sql_user]
                             k.config[:sql_password] = config[:sql_password]
                             k
                           end
      end

      def restore_user_sql
        k = ec_key_import
        k.config[:knife_ec_error_handler] = knife_ec_error_handler
        k.config[:skip_users_table] = false
        k.config[:skip_keys_table] = !config[:with_key_sql]
        k.config[:users_only] = true
        k.run
      end

      def restore_key_sql
        k = ec_key_import
        k.config[:skip_users_table] = true
        k.config[:skip_keys_table] = false
        k.config[:users_only] = false
        k.config[:clients_only] = true
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

          # Upload the admins, public_key_read_access and billing-admins groups and acls
          ui.msg "Restoring org admin data"
          chef_fs_config = Chef::ChefFS::Config.new

          # Handle Admins, Billing Admins and Public Key Read Access separately
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
          # public_key_read_access: Similarly for public_key_read_access,
          # the default permissions only give read/update to
          # pivotal and members of the admins group. Use the same strategy
          # above here.
          #
          groups = ['admins', 'billing-admins']
          groups.push('public_key_read_access') if
            ::File.exist?(::File.join(chef_fs_config.local_fs.child_paths['groups'], 'public_key_read_access.json'))

          groups.each do |group|
            restore_group(chef_fs_config, group, :clients => false)
          end

          acls_groups_paths = ['/acls/groups/billing-admins.json']
          acls_groups_paths.push('/acls/groups/public_key_read_access.json') if
            ::File.exist?(::File.join(chef_fs_config.local_fs.child_paths['acls'], 'groups', 'public_key_read_access.json'))

          acls_groups_paths.each do |acl|
            chef_fs_copy_pattern(acl, chef_fs_config)
          end

          Chef::Config.node_name = if config[:skip_version]
                                     org_admin
                                   else
                                     server.supports_defaulting_to_pivotal? ? 'pivotal' : org_admin
                                   end

          # Restore the entire org skipping the admin data and restoring groups and acls last
          ui.msg "Restoring the rest of the org"
          chef_fs_config = Chef::ChefFS::Config.new
          top_level_paths = chef_fs_config.local_fs.children.select { |entry| entry.name != 'acls' && entry.name != 'groups' }.map { |entry| entry.path }

          # Topologically sort groups for upload
          filenames = ['billing-admins.json', 'public_key_read_access.json']
          unsorted_groups = Chef::ChefFS::FileSystem.list(chef_fs_config.local_fs, Chef::ChefFS::FilePattern.new('/groups/*')).select { |entry| ! filenames.include?(entry.name) }.map { |entry| JSON.parse(entry.read) }
          group_paths = sort_groups_for_upload(unsorted_groups).map { |group_name| "/groups/#{group_name}.json" }

          group_acl_paths = Chef::ChefFS::FileSystem.list(chef_fs_config.local_fs, Chef::ChefFS::FilePattern.new('/acls/groups/*')).select { |entry| ! filenames.include?(entry.name) }.map { |entry| entry.path }
          acl_paths = Chef::ChefFS::FileSystem.list(chef_fs_config.local_fs, Chef::ChefFS::FilePattern.new('/acls/*')).select { |entry| entry.name != 'groups' }.map { |entry| entry.path }

          # Store organization data in a particular order:
          # - clients must be uploaded before groups (in top_level_paths)
          # - groups must be uploaded before any acl's
          # - groups must be uploaded twice to account for Chef Server versions that don't
          #   accept group members on POST
          (top_level_paths + group_paths*2 + group_acl_paths + acl_paths).each do |path|
            chef_fs_copy_pattern(path, chef_fs_config)
          end

          # restore clients to groups, using the pivotal user again
          Chef::Config[:node_name] = 'pivotal'
          groups.each do |group|
            restore_group(Chef::ChefFS::Config.new, group)
          end
         ensure
          Chef::Config.restore(old_config)
        end
      end

      # ChefFS copy pattern inside the EcRestore class will
      # copy from the local_fs to the Chef Server.
      #
      # NOTE: Do not get confused, this is the other way around
      # from how we implemented in EcBackup. Therefor we can't
      # abstract it inside EcBase.
      def chef_fs_copy_pattern(pattern_str, chef_fs_config)
        ui.msg "Copying #{pattern_str}"
        pattern = Chef::ChefFS::FilePattern.new(pattern_str)
        Chef::ChefFS::FileSystem.copy_to(pattern, chef_fs_config.local_fs,
                                         chef_fs_config.chef_fs, nil,
                                         config, ui,
                                         proc { |entry| chef_fs_config.format_path(entry) })
      rescue Net::HTTPServerException,
             Chef::ChefFS::FileSystem::NotFoundError,
             Chef::ChefFS::FileSystem::OperationFailedError => ex
        knife_ec_error_handler.add(ex)
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

        ui.msg "Copying /groups/#{group_name}.json"
        group = Chef::ChefFS::FileSystem.resolve_path(
          chef_fs_config.chef_fs,
          "/groups/#{group_name}.json"
        )

        # Will throw NotFoundError if JSON file does not exist on disk. See below.
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
      rescue Chef::ChefFS::FileSystem::NotFoundError
        Chef::Log.warn "Could not find #{group.display_path} on disk. Will not restore."
      end

      PERMISSIONS = %w{create read update delete grant}.freeze
      def put_acl(rest, url, acls)
        old_acls = rest.get(url)
        old_acls = Chef::ChefFS::DataHandler::AclDataHandler.new.normalize(old_acls, nil)
        acls = Chef::ChefFS::DataHandler::AclDataHandler.new.normalize(acls, nil)
        if acls != old_acls
          PERMISSIONS.each do |permission|
            rest.put("#{url}/#{permission}", { permission => acls[permission] })
          end
        end
      rescue Net::HTTPServerException => ex
        knife_ec_error_handler.add(ex)
      end
    end
  end
end
