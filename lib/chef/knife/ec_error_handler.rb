# Author:: Jeremy Miller (<jmiller@chef.io>)
# Copyright:: Copyright (c) 2013-2025 Progress Software Corporation and/or its subsidiaries or affiliates. All Rights Reserved.
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

      # Errors that are transient and should be logged but not halt the process.
      # These are connection-level or server-side failures that don't indicate
      # a bug in the client code.
      TRANSIENT_ERRORS = [
        Errno::ECONNRESET,       # Connection reset by peer
        Errno::ECONNREFUSED,     # Connection refused
        Errno::ETIMEDOUT,        # Connection timed out
        Errno::EHOSTUNREACH,     # No route to host
      ].freeze

      attr_reader :err_file, :error_count

      # Creates a new instance of the EcErrorHandler to start
      # adding errors during a backup or restore.
      #
      # Options:
      #   :suppress_exit - when true, skip the at_exit handler that
      #                    forces exit 1 on errors. Useful for testing.
      def initialize(working_dir, process, options = {})
        @err_dir = "#{working_dir}/errors"
        @error_count = 0
        @suppress_exit = options[:suppress_exit] || false
        FileUtils.mkdir_p(@err_dir)

        # Create an specific error file name depending
        # of where the process comes from.
        @err_file = if process == Chef::Knife::EcRestore
                      File.join(@err_dir, "restore-#{Time.now.iso8601}.json")
                    elsif process == Chef::Knife::EcBackup
                      File.join(@err_dir, "backup-#{Time.now.iso8601}.json")
                    else
                      File.join(@err_dir, "other-#{Time.now.iso8601}.json")
                    end

        # exit handler - display errors and set consistent exit status
        at_exit do
          unless @suppress_exit
            display(@err_file)
            # Ensure consistent exit status: exit 1 if errors occurred,
            # regardless of whether -VVV flag was used.
            # Only override if the process is exiting cleanly (status 0)
            # but errors were recorded.
            if has_errors? && ($!.nil? || $!.is_a?(SystemExit) && $!.success?)
              exit 1
            end
          end
        end
      end

      # Returns true if any errors have been recorded.
      def has_errors?
        @error_count > 0
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
        @error_count += 1

        msg = {
          timestamp:  Time.now,
          message:    ex.message,
          backtrace:  ex.backtrace,
          exception:  ex.class,
          transient:  transient_error?(ex)
        }

        if ex.respond_to?(:chef_rest_request=) && ex.chef_rest_request
          msg.merge!(
            req_path: ex.chef_rest_request.path,
            req_method: ex.chef_rest_request.method
          )
        elsif ex.respond_to?(:response) && ex.response
          msg.merge!(
            http_code: ex.response.code
          )
        elsif ex.instance_of?(Chef::ChefFS::FileSystem::NotFoundError)
          msg.merge!(
            entry: ex.entry,
            cause: ex.cause,
            reason: ex.reason
          )
        elsif ex.instance_of?(Chef::ChefFS::FileSystem::OperationFailedError)
          msg.merge!(
            entry: ex.entry,
            operation: ex.operation
          )
        end

        lock_file(@err_file, 'a') do |f|
          f.write(Chef::JSONCompat.to_json_pretty(msg))
        end
      end

      # Determines if the error is transient (network/server issue)
      # vs a permanent failure (client bug, bad data).
      def transient_error?(ex)
        return true if TRANSIENT_ERRORS.any? { |klass| ex.is_a?(klass) }
        # Net::HTTPFatalError covers 5xx responses (Internal Server Error)
        return true if ex.is_a?(Net::HTTPFatalError)
        # Net::HTTPServerException with 5xx code (older Ruby net/http)
        if ex.respond_to?(:response) && ex.response
          code = ex.response.code.to_i
          return true if code >= 500
        end
        false
      end

      # Why lock the error file?
      #
      # Well because ec-backup has a concurrency options that
      # will allow you to backup and restore things in parallel,
      # therefor we need to ensure that only one process is
      # writing to the error file.
      def lock_file(file_name, mode)
        File.open(file_name, mode) do |f|
          begin
            f.flock ::File::LOCK_EX
            yield f
          ensure
            f.flock ::File::LOCK_UN
          end
        end
      end

      def display(file_name = @err_file)
        # Print summary report only if error file exist
        return unless File.exist?(file_name)

        puts "\nError Summary Report"
        lock_file(file_name, 'r') do |f|
          f.each_line do |line|
            puts line
          end
        end
        puts "\nError(s) Summary file located at: '#{file_name}'"
      end
    end
  end
end
