require 'uri' unless defined?(URI)
require 'openssl' unless defined?(OpenSSL)
require 'chef/server_api'

class Chef
  class Server

    attr_accessor :root_url
    def initialize(root_url)
      @root_url = root_url
    end

    def self.from_chef_server_url(url)
      url = url.gsub(/\/organizations\/+[^\/]+\/*$/, '')
      Chef::Server.new(url)
    end

    def parse_server_version(line)
      # first line from the /version endpoint will either be this format "chef-server 12.17.5\n"
      # or, when habitat, this format "Package: chef-server/chef-server-nginx/12.17.42/20180413212943\n"
      Gem::Version.new(line.include?('/') ? line.split('/')[2] : line.split(' ').last.gsub(/\+.*$/, ''))
    end

    def version
      @version ||= begin
                     ver_line = Chef::ServerAPI.new(root_url).get('version').each_line.first
                     parse_server_version(ver_line)
                   end
    end

    def supports_user_acls?
      version >= Gem::Version.new("11.0.1")
    end

    def direct_account_access?
      Chef::ServerAPI.new("http://127.0.0.1:9465").get("users")
      true
    rescue
      false
    end

    def supports_defaulting_to_pivotal?
      version >= Gem::Version.new('12.1.0')
    end

    def supports_public_key_read_access?
      version >= Gem::Version.new('12.5.0')
    end
  end
end
