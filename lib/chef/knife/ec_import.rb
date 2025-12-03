require 'chef/knife'
require_relative 'ec_base'
require 'chef/json_compat'
require 'chef/chef_fs/config'
require 'chef/chef_fs/file_system'
require 'chef/chef_fs/file_pattern'
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

class Chef
  class Knife
    class EcImport < Chef::Knife

      include Knife::EcBase

      banner 'knife ec import DIRECTORY'

      # Constants for duplicated strings
      PUBLIC_KEY_READ_ACCESS_JSON = 'public_key_read_access.json'
      FROZEN_STATUS_KEY = 'frozen?'
      ADMIN_GROUPS = ['admins', 'billing-admins'].freeze
      ADMIN_GROUP_FILES = ['billing-admins.json', 'public_key_read_access.json'].freeze
      CONFLICT_STATUS = '409'
      NOT_FOUND_STATUS = '404'

      deps do
      end

      # Helper method to read JSON file from backup directory
      def read_json_file(path)
        JSONCompat.from_json(File.read(path))
      end

      # Helper method to construct organization file path
      def org_file_path(orgname, *path_parts)
        File.join(dest_dir, 'organizations', orgname, *path_parts)
      end

      # Helper method to construct organization URL
      def org_url(orgname, *path_parts)
        path = path_parts.join('/')
        path.empty? ? "organizations/#{orgname}" : "organizations/#{orgname}/#{path}"
      end

      # Helper method to construct cookbook URL
      def cookbook_url(org_name, cookbook_name, version, params = nil)
        url = org_url(org_name, 'cookbooks', cookbook_name, version)
        params ? "#{url}?#{params}" : url
      end

      # Helper method to handle HTTP calls with conflict (409) tolerance
      def http_request_ignore_conflicts(error_message = nil)
        yield
      rescue Net::HTTPClientException => ex
        if ex.response.code != CONFLICT_STATUS
          ui.error(error_message) if error_message
          knife_ec_error_handler.add(ex)
        end
      end

      # Helper method to create association request
      def create_association_request(orgname, username)
        rest.post(org_url(orgname, 'association_requests'), { 'user' => username })
      end

      # Helper method to accept association request
      def accept_association_request(username, association_id)
        rest.put("users/#{username}/association_requests/#{association_id}", { 'response' => 'accept' })
      end

      # Helper method to check if public key read access group exists
      def public_key_read_access_exists?(chef_fs_config, type = 'groups')
        ::File.exist?(::File.join(chef_fs_config.local_fs.child_paths[type], 'groups', PUBLIC_KEY_READ_ACCESS_JSON))
      end

      # Helper method to list ChefFS entries with pattern and filter
      def list_chef_fs_entries(chef_fs_config, pattern, exclude_files = [])
        Chef::ChefFS::FileSystem.list(chef_fs_config.local_fs, Chef::ChefFS::FilePattern.new(pattern))
          .select { |entry| !exclude_files.include?(entry.name) }
      end

      # Helper method to get admin groups based on what exists
      def get_admin_groups(chef_fs_config)
        groups = ADMIN_GROUPS.dup
        groups.push('public_key_read_access') if public_key_read_access_exists?(chef_fs_config, 'groups')
        groups
      end

      # Helper method to get admin group ACL paths
      def get_admin_group_acl_paths(chef_fs_config)
        acl_paths = ['/acls/groups/billing-admins.json']
        acl_paths.push('/acls/groups/public_key_read_access.json') if public_key_read_access_exists?(chef_fs_config, 'acls')
        acl_paths
      end

      def run
        set_dest_dir_from_args!
        set_client_config!
        ensure_webui_key_exists!
        set_skip_user_acl!

        warn_on_incorrect_clients_group(dest_dir, 'import')

        # Unlike restore, we do NOT restore users or user SQL data
        # We assume users already exist (managed by IAM)

        for_each_organization do |orgname|
          ui.msg "Importing organization[#{orgname}]"
          
          # Unlike restore, we do NOT create the organization
          # We validate it exists instead
          unless organization_exists?(orgname)
            ui.error("Organization #{orgname} does not exist. Skipping.")
            next
          end
          
          restore_open_invitations(orgname)
          add_users_to_org(orgname)
          upload_org_data(orgname)
        end

        # Unlike restore, we do NOT restore key SQL data

        if config[:skip_useracl]
          ui.warn('Skipping user ACL update. To update user ACLs, remove --skip-useracl.')
        else
          restore_user_acls
        end

        completion_banner
      end

      def organization_exists?(orgname)
        rest.get(org_url(orgname))
        true
      rescue Net::HTTPClientException => ex
        if ex.response.code == NOT_FOUND_STATUS
          false
        else
          knife_ec_error_handler.add(ex)
          false
        end
      end

      def restore_open_invitations(orgname)
        invitations = read_json_file(org_file_path(orgname, 'invitations.json'))
        invitations.each do |invitation|
          http_request_ignore_conflicts("Cannot create invitation #{invitation['id']}") do
            create_association_request(orgname, invitation['username'])
          end
        end
      end

      def add_users_to_org(orgname)
        members = read_json_file(org_file_path(orgname, 'members.json'))
        members.each do |member|
          username = member['user']['username']
          http_request_ignore_conflicts do
            response = create_association_request(orgname, username)
            association_id = response['uri'].split('/').last
            accept_association_request(username, association_id)
          end
        end
      end

      def restore_user_acls
        ui.msg 'Restoring user ACLs'
        for_each_user do |name|
          user_acl = read_json_file(File.join(dest_dir, 'user_acls', "#{name}.json"))
          put_acl(user_acl_rest, "users/#{name}/_acl", user_acl)
        end
      end

      def for_each_user
        Dir.foreach("#{dest_dir}/users") do |filename|
          next if filename !~ /(.+)\.json/
          name = $1
          # We don't have overwrite_pivotal option, but we should probably still skip pivotal if it's in the backup
          # to avoid messing with the system user, although we are only doing ACLs here.
          if name == 'pivotal'
             # In restore, we skip pivotal unless overwrite_pivotal is true.
             # Here we don't have that flag, so we should probably always skip pivotal for safety
             # as we are not managing users.
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
          ui.msg 'Restoring org admin data'
          chef_fs_config = Chef::ChefFS::Config.new

          # Handle Admins, Billing Admins and Public Key Read Access separately
          groups = get_admin_groups(chef_fs_config)

          groups.each do |group|
            restore_group(chef_fs_config, group, :clients => false)
          end

          acls_groups_paths = get_admin_group_acl_paths(chef_fs_config)

          acls_groups_paths.each do |acl|
            chef_fs_copy_pattern(acl, chef_fs_config)
          end

          Chef::Config.node_name = if config[:skip_version]
                                     org_admin
                                   else
                                     server.supports_defaulting_to_pivotal? ? 'pivotal' : org_admin
                                   end

          # Restore the entire org skipping the admin data and restoring groups and acls last
          ui.msg 'Restoring the rest of the org'
          chef_fs_config = Chef::ChefFS::Config.new
          top_level_paths = chef_fs_config.local_fs.children.select { |entry| entry.name != 'acls' && entry.name != 'groups' }.map { |entry| entry.path }

          # Topologically sort groups for upload
          unsorted_groups = list_chef_fs_entries(chef_fs_config, '/groups/*', ADMIN_GROUP_FILES)
                              .map { |entry| JSON.parse(entry.read) }
          group_paths = sort_groups_for_upload(unsorted_groups).map { |group_name| "/groups/#{group_name}.json" }

          group_acl_paths = list_chef_fs_entries(chef_fs_config, '/acls/groups/*', ADMIN_GROUP_FILES)
                              .map { |entry| entry.path }
          acl_paths = Chef::ChefFS::FileSystem.list(chef_fs_config.local_fs, Chef::ChefFS::FilePattern.new('/acls/*'))
                        .select { |entry| entry.name != 'groups' }
                        .map { |entry| entry.path }

          # Store organization data in a particular order:
          # - clients must be uploaded before groups (in top_level_paths)
          # - groups must be uploaded before any acl's
          # - groups must be uploaded twice to account for Chef Infra Server versions that don't
          #   accept group members on POST
          (top_level_paths + group_paths*2 + group_acl_paths + acl_paths).each do |path|
            chef_fs_copy_pattern(path, chef_fs_config)
          end

          # Apply frozen status to cookbooks after they are uploaded
          restore_cookbook_frozen_status(name, chef_fs_config)

          # restore clients to groups, using the pivotal user again
          Chef::Config[:node_name] = 'pivotal'
          groups.each do |group|
            restore_group(Chef::ChefFS::Config.new, group)
          end
         ensure
          Chef::Config.restore(old_config)
        end
      end

      def chef_fs_copy_pattern(pattern_str, chef_fs_config)
        ui.msg "Copying #{pattern_str}"
        pattern = Chef::ChefFS::FilePattern.new(pattern_str)
        Chef::ChefFS::FileSystem.copy_to(pattern, chef_fs_config.local_fs,
                                         chef_fs_config.chef_fs, nil,
                                         config, ui,
                                         proc { |entry| chef_fs_config.format_path(entry) })
      rescue Net::HTTPClientException,
             Chef::ChefFS::FileSystem::NotFoundError,
             Chef::ChefFS::FileSystem::OperationFailedError => ex
        knife_ec_error_handler.add(ex)
      end

      def sort_groups_for_upload(groups)
        Chef::Tsorter.new(group_array_to_sortable_hash(groups)).tsort
      end

      def group_array_to_sortable_hash(groups)
        ret = {}
        groups.each do |group|
          name = group['name']
          ret[name] = if group.key?('groups')
                        group['groups']
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
          if includes[:users] && includes[:clients]
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

      def restore_cookbook_frozen_status(org_name, chef_fs_config)
        return if config[:skip_frozen_cookbook_status]

        ui.msg 'Restoring cookbook frozen status'
        cookbooks_path = org_file_path(org_name, 'cookbooks')

        return unless File.directory?(cookbooks_path)

        Dir.foreach(cookbooks_path) do |cookbook_entry|
          next if cookbook_entry == '.' || cookbook_entry == '..'
          
          process_cookbook_frozen_status(cookbooks_path, cookbook_entry, org_name)
        end
      end

      def process_cookbook_frozen_status(cookbooks_path, cookbook_entry, org_name)
        cookbook_path = File.join(cookbooks_path, cookbook_entry)
        return unless File.directory?(cookbook_path)

        # cookbook_entry is in format "cookbook_name-version"
        # Extract cookbook name and version
        # Use non-greedy match and more specific pattern to avoid ReDoS
        return unless cookbook_entry =~ /^(.+?)-(\d+\.\d+\.\d+(?:\..+)?)$/
        
        cookbook_name = $1
        version = $2

        status_file = File.join(cookbook_path, 'status.json')
        return unless File.exist?(status_file)

        begin
          status_data = JSON.parse(File.read(status_file))
          freeze_cookbook(cookbook_name, version, org_name) if status_data['frozen'] == true
        rescue JSON::ParserError => e
          ui.warn "Failed to parse status.json for #{cookbook_name} #{version}: #{e.message}"
        rescue => e
          ui.warn "Failed to restore frozen status for #{cookbook_name} #{version}: #{e.message}"
        end
      end

      def freeze_cookbook(cookbook_name, version, org_name)
        ui.msg "Freezing cookbook #{cookbook_name} version #{version}"

        # Get the current cookbook manifest
        manifest = rest.get(cookbook_url(org_name, cookbook_name, version))

        if manifest[FROZEN_STATUS_KEY] # Ignore if already frozen
          ui.warn "Freezing cookbook #{cookbook_name} version #{version} skipped since it is already frozen!"
          return
        end

        rest.put(cookbook_url(org_name, cookbook_name, version, 'freeze=true'), 
                 manifest.tap { |h| h[FROZEN_STATUS_KEY] = true })
      rescue Net::HTTPClientException => ex
        ui.warn "Failed to freeze cookbook #{cookbook_name} #{version}: #{ex.message}"
        knife_ec_error_handler.add(ex)
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
      rescue Net::HTTPClientException => ex
        knife_ec_error_handler.add(ex)
      end
    end
  end
end
