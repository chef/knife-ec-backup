require 'uri'
require 'openssl'
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

    def version
      @version ||= begin
                     uri = URI.parse("#{root_url}/version")
                     ver_line = open(uri, {ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE}).each_line.first
                     ver_string = ver_line.split(' ').last
                     ver_string = ver_string.gsub(/\+.*$/, '')
                     Gem::Version.new(ver_string)
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
  end
end
