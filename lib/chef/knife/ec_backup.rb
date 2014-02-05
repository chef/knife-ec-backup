require 'chef/knife'

class Chef
  class Knife
    class EcBackup < Chef::Knife
      banner 'knife ec backup'

      include Knife::EcBase

      deps do
        require 'chef_fs/config'
        require 'chef_fs/file_system'
        require 'chef_fs/file_pattern'
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

        ui.msg 'Backing up users..'
        backup_users(dest_dir, rest)
        unless config[:skip_useracl]
          ui.msg 'Backing up user acls...'
          backup_user_acls(dest_dir, user_acl_rest)
        end
        ui.msg 'Backing up organizations...'
        backup_orgs(dest_dir, rest, webui_key)
      end

      def backup_users(dest_dir, rest)
        ensure_dir("#{dest_dir}/users")
        rest.get_rest('/users').each_pair do |name, url|
          File.open("#{dest_dir}/users/#{name}.json", 'w') do |file|
            file.write(Chef::JSONCompat.to_json_pretty(rest.get_rest(url)))
          end
        end
      end

      def backup_user_acls(dest_dir, user_acl_rest)
        ensure_dir("#{dest_dir}/user_acls")
        rest.get_rest('/users').each_pair do |name, url|
          File.open("#{dest_dir}/user_acls/#{name}.json", 'w') do |file|
            file.write(Chef::JSONCompat.to_json_pretty(user_acl_rest.get_rest("users/#{name}/_acl")))
          end
        end
      end

      def ensure_dir(dir)
        Dir.mkdir(dir) unless File.exist?(dir)
      end

      def backup_orgs(dest_dir, rest, webui_key)
        ensure_dir("#{dest_dir}/organizations")
        rest.get_rest('/organizations').each_pair do |name, url|
          org = rest.get_rest(url)
          if org['assigned_at']
            ui.msg "Downloading organization #{name} ..."
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
      end

      def download_org(dest_dir, webui_key, name)
        ::ChefConfigMutator.save_config!
        error = false
        begin
          ::ChefConfigMutator.set_config_for_org!(name, dest_dir)

          ensure_dir(Chef::Config.chef_repo_path)

          # Download the billing-admins ACL and group as pivotal
          chef_fs_config = ::ChefFS::Config.new
          ['/acls/groups/billing-admins.json', '/groups/billing-admins.json', '/groups/admins.json'].each do |path|
            pattern = ::ChefFS::FilePattern.new(path)
            ::ChefFS::FileSystem.copy_to(pattern, chef_fs_config.chef_fs, chef_fs_config.local_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) })
          end

          ::ChefConfigMutator.config_for_auth_as!(org_admin)

          # Download the entire org skipping the billing admins group ACL and the group itself
          chef_fs_config = ::ChefFS::Config.new

          top_level_paths = chef_fs_config.chef_fs.children.select { |entry| entry.name != 'acls' && entry.name != 'groups' }.map { |entry| entry.path }
          acl_paths = ::ChefFS::FileSystem.list(chef_fs_config.chef_fs, ::ChefFS::FilePattern.new('/acls/*')).select { |entry| entry.name != 'groups' }.map { |entry| entry.path }
          group_acl_paths = ::ChefFS::FileSystem.list(chef_fs_config.chef_fs, ::ChefFS::FilePattern.new('/acls/groups/*')).select { |entry| entry.name != 'billing-admins.json' }.map { |entry| entry.path }
          group_paths = ::ChefFS::FileSystem.list(chef_fs_config.chef_fs, ::ChefFS::FilePattern.new('/groups/*')).select { |entry| entry.name != 'billing-admins.json' }.map { |entry| entry.path }

          (top_level_paths + group_acl_paths + acl_paths + group_paths).each do |path|
            ::ChefFS::FileSystem.copy_to(::ChefFS::FilePattern.new(path), chef_fs_config.chef_fs, chef_fs_config.local_fs, nil, config, ui, proc { |entry| chef_fs_config.format_path(entry) })
          end
        ensure
          ::ChefConfigMutator.restore_config!
        end
      end
    end
  end
end
