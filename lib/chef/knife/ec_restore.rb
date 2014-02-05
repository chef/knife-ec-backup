require 'chef/knife'
require 'chef/knife/ec_base'

class Chef
  class Knife
    class EcRestore < Chef::Knife
      banner 'knife ec restore'

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
        require 'knife_ec_backup/mutator'
      end

      def run
        if name_args.length <= 0
          ui.error('Must specify backup directory as an argument.')
          exit 1
        end

        dest_dir = name_args[0]
        webui_key = config[:webui_key]

        ::ChefConfigMutator.set_initial_client_config!(webui_key)
        assert_exists!(webui_key)

        rest = Chef::REST.new(Chef::Config.chef_server_root)
        user_acl_rest = setup_user_acl_rest! unless config[:skip_useracl]

        ui.msg 'Restoring users...'
        restore_users(dest_dir, rest)
        ui.msg 'Restoring orgs...'
        restore_orgs(dest_dir, rest, webui_key)
        unless config[:skip_useracls]
          ui.msg 'Restoring user_acls'
          restore_user_acls(dest_dir, user_acl_rest)
        end
      end

      def restore_users(dest_dir, rest)
        Dir.glob("#{dest_dir}/users/*.json") do |filename|
          name = ::File.basename(filename).gsub('.json', '')
          if name == 'pivotal' && !config[:overwrite_pivotal]
            ui.warn('Skipping pivotal update.  To overwrite pivotal, pass --overwrite-pivotal.')
          else
            # Update user object
            user = JSONCompat.from_json(IO.read(filename))
            begin
              # Supply password for new user
              user_with_password = user.dup
              user_with_password['password'] = SecureRandom.hex
              rest.post_rest('users', user_with_password)
            rescue Net::HTTPServerException => e
              if e.response.code == '409'
                rest.put_rest("users/#{name}", user)
              else
                raise
              end
            end
          end
        end
      end

      def restore_orgs(dest_dir, rest, webui_key)
        Dir.glob("#{dest_dir}/organizations/*/").map {|p| p.split('/').last }.each do |name|
          ui.msg "Restoring org #{name} ..."
          create_org(dest_dir, rest, name)
          restore_invitations(dest_dir, rest, name)
          reassociate_users(dest_dir, rest, name)
          upload_org(dest_dir, webui_key, rest, name)
        end
      end

      def create_org(dest_dir, rest, name)
        org = JSONCompat.from_json(IO.read("#{dest_dir}/organizations/#{name}/org.json"))
        begin
          rest.post_rest('organizations', org)
        rescue Net::HTTPServerException => e
          if e.response.code == '409'
            rest.put_rest("organizations/#{name}", org)
          else
            raise
          end
        end
      end

      def restore_invitations(dest_dir, rest, name)
        invitations = JSONCompat.from_json(IO.read("#{dest_dir}/organizations/#{name}/invitations.json"))
        invitations.each do |invitation|
          begin
            rest.post_rest("organizations/#{name}/association_requests", 'user' => invitation['username'])
          rescue Net::HTTPServerException => e
            raise if e.response.code != '409'
          end
        end
      end

      def reassociate_users(dest_dir, rest, name)
        members = JSONCompat.from_json(IO.read("#{dest_dir}/organizations/#{name}/members.json"))
        members.each do |member|
          username = member['user']['username']
          begin
            response = rest.post_rest("organizations/#{name}/association_requests", 'user' => username)
            association_id = response['uri'].split('/').last
            rest.put_rest("users/#{username}/association_requests/#{association_id}", 'response' => 'accept')
          rescue Net::HTTPServerException => e
            raise if e.response.code != '409'
          end
        end
      end

      def restore_user_acls(dest_dir, user_acl_rest)
        ui.msg 'Restoring user ACLs ...'
        Dir.glob("#{dest_dir}/users/*.json") do |filename|
          name = ::File.basename(filename).gsub('.json', '')
          if name == 'pivotal' && !config[:overwrite_pivotal]
            ui.warn('Skipping pivotal update.  To overwrite pivotal, pass --overwrite-pivotal.')
          else
            # Update user acl
            user_acl = JSONCompat.from_json(IO.read("#{dest_dir}/user_acls/#{name}.json"))
            put_acl(user_acl_rest, "users/#{name}/_acl", user_acl)
          end
        end
      end

      def upload_org(dest_dir, webui_key, rest, name)
        ::ChefConfigMutator.save_config!
        begin
          ::ChefConfigMutator.set_config_for_org!(name, dest_dir)

          # Upload the admins group and billing-admins acls
          puts 'Restoring the org admin data'
          chef_fs_config = ::ChefFS::Config.new

          # Restore users w/o clients (which don't exist yet)
          ['admins', 'billing-admins'].each do |group|
            restore_group(chef_fs_config, group, :clients => false)
          end

          pattern = ::ChefFS::FilePattern.new('/acls/groups/billing-admins.json')
          ::ChefFS::FileSystem.copy_to(pattern, chef_fs_config.local_fs, chef_fs_config.chef_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) })

          admin = org_admin
          ::ChefConfigMutator.config_for_auth_as!(admin)

          # Restore the entire org skipping the admin data and restoring groups and acls last
          ui.msg 'Restoring the rest of the org'
          chef_fs_config = ::ChefFS::Config.new
          top_level_paths = chef_fs_config.local_fs.children.select { |entry| entry.name != 'acls' && entry.name != 'groups' }.map { |entry| entry.path }
          acl_paths = ::ChefFS::FileSystem.list(chef_fs_config.local_fs, ::ChefFS::FilePattern.new('/acls/*')).select { |entry| entry.name != 'groups' }.map { |entry| entry.path }
          group_acl_paths = ::ChefFS::FileSystem.list(chef_fs_config.local_fs, ::ChefFS::FilePattern.new('/acls/groups/*')).select { |entry| entry.name != 'billing-admins.json' }.map { |entry| entry.path }
          group_paths = ::ChefFS::FileSystem.list(chef_fs_config.local_fs, ::ChefFS::FilePattern.new('/groups/*')).select { |entry| entry.name != 'billing-admins.json' }.map { |entry| entry.path }
          (top_level_paths + group_paths + group_acl_paths + acl_paths).each do |path|
            ::ChefFS::FileSystem.copy_to(::ChefFS::FilePattern.new(path), chef_fs_config.local_fs, chef_fs_config.chef_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) })
          end

          # restore clients to groups, using the pivotal key again
          ::ChefConfigMutator.config_for_auth_as!('pivotal')
          ['admins', 'billing-admins'].each do |group|
            restore_group(::ChefFS::Config.new, group, :users => false)
          end
        ensure
          ::ChefConfigMutator.restore_config!
        end
      end

      def restore_group(chef_fs_config, group_name, includes = { :users => true, :clients => true })
        includes[:users] = true unless includes.key? :users
        includes[:clients] = true unless includes.key? :clients

        group = ::ChefFS::FileSystem.resolve_path(chef_fs_config.chef_fs,
                                                  "/groups/#{group_name}.json")

        members_json = ::ChefFS::FileSystem.resolve_path(chef_fs_config.local_fs,
                                                         "/groups/#{group_name}.json").read

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
            rest.put_rest("#{url}/#{permission}", permission => acls[permission])
          end
        end
      end
    end
  end
end
