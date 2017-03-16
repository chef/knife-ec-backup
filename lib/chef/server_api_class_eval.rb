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
      context = { url: @url, req_path: req_path, options: @options }
      ex.knife_ec_backup_rest_request = context
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
