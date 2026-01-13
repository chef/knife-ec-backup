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
      version_str = if line.include?('/')
                      line.split('/')[2]
                    else
                      # Strip everything after '+' using String#partition.
                      # We avoid regex here since Ruby < 3.2 is vulnerable to ReDoS,
                      # and we support Ruby 3.1 in pipelines.
                      line.split(' ').last.partition('+').first
                    end

      Gem::Version.new(version_str)
    end

    def version
      @version ||= begin
                     version_response = Chef::ServerAPI.new(root_url).get('version')
                     
                     # Handle both text response (chef-server) and JSON response (dsm-nginx)
                     if version_response.is_a?(Hash)
                       # JSON response from dsm-nginx: {"version": "v1.3.27", ...}
                       version_string = version_response['version'] || version_response[:version] || 'unknown'
                       # Remove 'v' prefix if present (e.g., "v1.3.27" -> "1.3.27")
                       version_string = version_string.start_with?('v') ? version_string[1..-1] : version_string
                       Gem::Version.new(version_string)
                     else
                       # Text response from chef-server: "chef-server 12.17.5\n" or habitat format
                       ver_line = version_response.each_line.first
                       parse_server_version(ver_line)
                     end
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
