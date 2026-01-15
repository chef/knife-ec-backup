#
# Author:: Steven Danna (<steve@chef.io>)
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
#

class Chef
  class OrgIdCache
    NO_ORG = "not here"

    attr_accessor :db, :cache
    def initialize(db)
      @db = db
      @cache = {}
    end

    def fetch(org_name)
      if cache.key?(org_name) && cache[org_name] != NO_ORG
        cache[org_name]
      elsif cache.key?(org_name) && cache[org_name] == NO_ORG
        nil
      else
        r = db.select(:id).from(:orgs).where(:name => org_name).first
        if r.nil?
          store(org_name, NO_ORG)
          nil
        else
          store(org_name, r[:id])
          r[:id]
        end
      end
    end

    def store(org_name, org_guid)
      cache[org_name] = org_guid
    end
  end
end
