# This class makes me deeply sad.
#
# Throughout Knife::EcBackup and Knife::EcRestore we mutate
# Chef::Config in order to influence underlying ChefFS and Chef::REST
# objects. There must be a better way.  For now, this class contains
# the sadness.

class ChefConfigMutator
  PATHS = %w(chef_repo_path cookbook_path environment_path data_bag_path role_path node_path client_path acl_path group_path container_path)
  CONFIG_VARS = %w(chef_server_url chef_server_root custom_http_headers node_name client_key versioned_cookbooks) + PATHS

  def self.clear_path_config!
    PATHS.each { |path_var| Chef::Config[path_var.to_sym] = nil }
  end

  def self.save_config!
    @@old_config = CONFIG_VARS.inject({}) {|memo, key| memo[key] = Chef::Config[key.to_sym]; memo}
  end

  def self.restore_config!
    CONFIG_VARS.each {|key| Chef::Config[key.to_sym] = @@old_config[key] }
  end

  def self.config_for_auth_as!(user = 'pivotal')
    Chef::Config.node_name = user
    if user == "pivotal" || user.nil?
      Chef::Config.client_key = @@old_config['client_key']
      Chef::Config.custom_http_headers = @@old_config['custom_http_headers']
    else
      Chef::Config.client_key = Chef::Config[:webui_key]
      Chef::Config.custom_http_headers = (Chef::Config.custom_http_headers || {}).merge('x-ops-request-source' => 'web')
    end
  end

  def self.set_config_for_org!(orgname, dest_dir)
    self.clear_path_config!
    Chef::Config.chef_repo_path = "#{dest_dir}/organizations/#{orgname}"
    Chef::Config.versioned_cookbooks = true
    Chef::Config.chef_server_url = "#{Chef::Config.chef_server_root}/organizations/#{orgname}"
  end

  # Assumes that if the user set node_name to "pivotal"
  # already, they know what they are doing
  def self.set_initial_client_config!(webui_key)
    if Chef::Config.node_name != 'pivotal'
      unless File.exist?('/etc/opscode/pivotal.pem')
        ui.error('Username not configured as pivotal and /etc/opscode/pivotal.pem does not exist.  It is recommended that you run this plugin from your Chef server.')
        exit 1
      end
      Chef::Config.node_name = 'pivotal'
      Chef::Config.client_key = '/etc/opscode/pivotal.pem'
    end

    if Chef::Config.chef_server_root.nil?
      Chef::Config.chef_server_root = Chef::Config.chef_server_url.gsub(%r{/organizations/+[^\/]+/*$}, '')
      ui.warn "chef_server_root not found in knife configuration. Setting root #{Chef::Config.chef_server_root}"
    end
    Chef::Config.webui_key = webui_key
  end
end
