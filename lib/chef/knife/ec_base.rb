#
# Author:: Steven Danna (<steve@getchef.com>)
# Copyright:: Copyright (c) 2014 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/knife'

class Chef
  class Knife
    module EcBase
      def self.included(includer)
        includer.class_eval do

          option :concurrency,
            :long => '--concurrency THREADS',
            :description => 'Maximum number of simultaneous requests to send (default: 10)'

          option :webui_key,
            :long => '--webui-key KEYPATH',
            :description => 'Path to the WebUI Key (default: /etc/opscode/webui_priv.pem)',
            :default => '/etc/opscode/webui_priv.pem'

          option :skip_useracl,
            :long => '--skip-useracl',
            :boolean => true,
            :default => false,
            :description => "Skip downloading user ACLs.  This is required for EC 11.0.0 and lower"

          option :skip_version,
            :long => '--skip-version-check',
            :boolean => true,
            :default => false,
            :description => "Skip checking the Chef Server version and auto-configuring options."
        end
      end

      def configure_chef
        super
        Chef::Config[:concurrency] = config[:concurrency].to_i if config[:concurrency]
        ::ChefFS::Parallelizer.threads = (Chef::Config[:concurrency] || 10) - 1
      end

      # Mutates Chef::Config to use pivotal key
      # Assumes that if the user set node_name to "pivotal"
      # already, they know what they are doing
      def set_client_config!
        if Chef::Config.node_name != "pivotal"
          if !File.exist?("/etc/opscode/pivotal.pem")
            ui.error("Username not configured as pivotal and /etc/opscode/pivotal.pem does not exist.  It is recommended that you run this plugin from your Chef server.")
            exit 1
          end
          Chef::Config.node_name = 'pivotal'
          Chef::Config.client_key = '/etc/opscode/pivotal.pem'
        end

        if Chef::Config.chef_server_root.nil?
          Chef::Config.chef_server_root = Chef::Config.chef_server_url.gsub(/\/organizations\/+[^\/]+\/*$/, '')
          ui.warn "chef_server_root not found in knife configuration. Setting root #{Chef::Config.chef_server_root}"
        end
      end

      def assert_exists!(path)
        if ! File.exist?(path)
          ui.error "#{path} does not exist!"
          exit 1
        end
      end
    end
  end
end
