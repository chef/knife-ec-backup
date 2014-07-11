require 'uri'
require 'openssl'

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
                     Gem::Version.new(ver_string)
                   end
    end

    def supports_user_acls?
      version >= Gem::Version.new("11.0.1")
    end

    def direct_account_access?
      Chef::REST.new("http://127.0.0.1:9465").get("users")
      true
    rescue
      false
    end
  end
end
