# Author:: Jeremy Miller (<jmiller@chef.io>)
# Copyright:: Copyright (c) 2017 Chef Software, Inc.
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

class Chef
  class Knife
    # This class handles the errors that we might encounter on a
    # backup or restore, it stors the errors inside a specific file
    # inside the working directory.
    class EcErrorHandler

      # Creates a new instance of the EcErrorHandler to start
      # adding errors during a backup or restore.
      def initialize(working_dir, process)
        @err_dir = File.join(working_dir, 'errors')
        FileUtils.mkdir_p(@err_dir)

        @err_file = case process
          when Chef::Knife::EcRestore
            File.join(@err_dir, "restore-#{Time.now.iso8601}.json")
          when Chef::Knife::EcBackup
            File.join(@err_dir, "backup-#{Time.now.iso8601}.json")
          else
            File.join(@err_dir, "other-#{Time.now.iso8601}.json")
        end

        # exit handler
        at_exit { EcErrorHandler.display(@err_file) }
      end

      # Add an exception to the error file.
      #
      # For now we are writing all the errors to a single file, but
      # in the future we would like to be able to generate a full path
      # just as we do when we are backing up the Server, just that putting
      # the file inside `{work_dir}/errors/{path}`
      #
      # Example:
      # A failed user
      # => {work_dir}/errors/users/afiune.json
      # A failed cookbook
      # => {work_dir}/errors/cookbooks/burger.json
      # A failed environment
      # => {work_dir}/errors/environment/dev.json
      #
      # The advantages of this schema is the ability to retry the backup or
      # restore and pick up where we left.
      def add(ex)
        msg = {
          timestamp:  Time.now,
          message:    ex.message,
          backtrace:  ex.backtrace
        }
        if ex.respond_to?(:knife_ec_backup_rest_request=)
          msg.merge!(ex.knife_ec_backup_rest_request)
        end
        EcErrorHandler.lock_file(@err_file, 'a') do |f|
          f.write(Chef::JSONCompat.to_json_pretty(msg))
        end
      end

      def self.lock_file(file_name, mode)
        File.open(file_name, mode) do |f|
          begin
            f.flock File::LOCK_EX
            yield f
          ensure
            f.flock File::LOCK_UN
          end
        end
      end

      def self.display(file_name)
        puts "\nError Summary Report"
        EcErrorHandler.lock_file(file_name, 'r') do |f|
          f.each_line do |line|
            puts line
          end
        end
        puts "\nError(s) Summary file located at: '#{file_name}'"
      end
    end
  end
end

# Openning the ServerAPI class to inject the HTTP request context into
# any `Net::HTTPServerException` exception, overriding the get, put, post
# and delete methods, incorporating a `rescue` block in each, adding the
# extra context from instance variables as well as the request path to the
# object, then bubbling the error up in the stack with raise.
Chef::ServerAPI.class_eval do
  # ChefKnifeEcBackupNetHTTPExceptionExtensions
  module ChefKnifeEcBackupNetHTTPExceptionExtensions
    attr_accessor :knife_ec_backup_rest_request
  end

  require 'net/http'
  module Net
    # HTTPServerException
    class HTTPServerException
      include ChefKnifeEcBackupNetHTTPExceptionExtensions
    end
  end

  def knife_ec_backup_rest_exception_add_context(ex, req_path)
    if ex.respond_to?(:knife_ec_backup_rest_request=)
      ex.knife_ec_backup_rest_request = { url: @url, req_path: req_path, options: @options }
    end
  end

  def get(req_path, headers = {})
    super
  rescue Net::HTTPServerException => ex
    knife_ec_backup_rest_exception_add_context(ex, req_path)
    raise
  end

  def post(req_path, headers = {})
    super
  rescue Net::HTTPServerException => ex
    knife_ec_backup_rest_exception_add_context(ex, req_path)
    raise
  end

  def put(req_path, headers = {})
    super
  rescue Net::HTTPServerException => ex
    knife_ec_backup_rest_exception_add_context(ex, req_path)
    raise
  end

  def delete(req_path, headers = {})
    super
  rescue Net::HTTPServerException => ex
    knife_ec_backup_rest_exception_add_context(ex, req_path)
    raise
  end
end
