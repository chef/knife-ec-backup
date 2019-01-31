# knife-ec-backup Change Log

<!-- latest_release 2.2.0 -->
## [v2.2.0](https://github.com/chef/knife-ec-backup/tree/v2.2.0) (2017-06-27)

#### Merged Pull Requests
* [knife-ec-backup #123](https://github.com/chef/knife-ec-backup/pull/123) Default skip_ids to true when restoring with sql options.
* [knife-ec-backup #122](https://github.com/chef/knife-ec-backup/pull/122) Bump to 2.3.0.

* [knife-ec-backup #121](https://github.com/chef/knife-ec-backup/pull/121) Warn when clients group appears incorrect.
* [knife-ec-backup #120](https://github.com/chef/knife-ec-backup/pull/120) Support server version when habitat.
* [knife-ec-backup #115](https://github.com/chef/knife-ec-backup/pull/115) Removed Ruby 1.9 support in the Gemfile.
* [knife-ec-backup #114](https://github.com/chef/knife-ec-backup/pull/114) [SUSTAIN-657] Handle and report user restore fails.
* [knife-ec-backup #112](https://github.com/chef/knife-ec-backup/pull/112) Bumped patch to 2.2.3.

* [knife-ec-backup #111](https://github.com/chef/knife-ec-backup/pull/111) Completion msg.
* [knife-ec-backup #110](https://github.com/chef/knife-ec-backup/pull/110) Added rescue for Chef::ChefFS::FileSystem::NotFoundError.
* [knife-ec-backup #109](https://github.com/chef/knife-ec-backup/pull/109) Bump patch number.
* [knife-ec-backup #106](https://github.com/chef/knife-ec-backup/pull/106) Backporting support for server < 12.5.0.
* [knife-ec-backup #105](https://github.com/chef/knife-ec-backup/pull/105) Test on supported Ruby releases.
* [knife-ec-backup #104](https://github.com/chef/knife-ec-backup/pull/104) Bump version to 2.2.1

* [knife-ec-backup #102](https://github.com/chef/knife-ec-backup/pull/102) Minor travis improvements.
* [knife-ec-backup #101](https://github.com/chef/knife-ec-backup/pull/101) Removed stray require.
* [knife-ec-backup #100](https://github.com/chef/knife-ec-backup/pull/100) Hardcode PERMISSIONS list.
* [knife-ec-backup #99](https://github.com/chef/knife-ec-backup/pull/99) Bump minor version to 2.2.0

* [knife-ec-backup #98](https://github.com/chef/knife-ec-backup/pull/98) Removed Gemfile.lock.
* [knife-ec-backup #94](https://github.com/chef/knife-ec-backup/pull/94) Added acl matching for subpaths and leafs.
* [knife-ec-backup #93](https://github.com/chef/knife-ec-backup/pull/93) Added Gemfile.lock.
* [knife-ec-backup #92](https://github.com/chef/knife-ec-backup/pull/92) jeremymv2/purge users.
* [knife-ec-backup #91](https://github.com/chef/knife-ec-backup/pull/91) Get sql-password from veil as well.
* [knife-ec-backup #90](https://github.com/chef/knife-ec-backup/pull/90) New EcErrorHandler to catch HTTP failures avoiding crashes.
* [knife-ec-backup #89](https://github.com/chef/knife-ec-backup/pull/89) Use veil to retrieve the webui key by default.
* [knife-ec-backup #88](https://github.com/chef/knife-ec-backup/pull/88) Substituting org_admin for user pivotal.
* [knife-ec-backup #87](https://github.com/chef/knife-ec-backup/pull/87) Exposing purge, dry_run options with sane defaults.
* [knife-ec-backup #86](https://github.com/chef/knife-ec-backup/pull/86) Swallow errors when restoring files that do not exist.
* [knife-ec-backup #80](https://github.com/chef/knife-ec-backup/pull/80) Prevent "No such file or directory on remote or local" errors.
* [knife-ec-backup #79](https://github.com/chef/knife-ec-backup/pull/79) Added public_key_read_access.
* [knife-ec-backup #71](https://github.com/chef/knife-ec-backup/pull/71) Removed debug code from prior fix.
* [knife-ec-backup #70](https://github.com/chef/knife-ec-backup/pull/70) 2.0.6: use correctly quoted literal in EcKeyBase and add tests.
* [knife-ec-backup #69](https://github.com/chef/knife-ec-backup/pull/69) Make EcKeyBase aware of the new location of db keys.
* [knife-ec-backup #68](https://github.com/chef/knife-ec-backup/pull/68) Forgot to require chef/server_api and use V0 for admins.
* [knife-ec-backup #67](https://github.com/chef/knife-ec-backup/pull/67) Updated rests in ec_base to use API V0.
* [knife-ec-backup #65](https://github.com/chef/knife-ec-backup/pull/65) Fix typo in readme.
* [knife-ec-backup #63](https://github.com/chef/knife-ec-backup/pull/63) Install on Enterprise Chef 11.
* [knife-ec-backup #61](https://github.com/chef/knife-ec-backup/pull/61) Only skip keys table on user restore if config[:with_key_sql] is false.
* [knife-ec-backup #60](https://github.com/chef/knife-ec-backup/pull/60) Updated README.md.
* [knife-ec-backup #53](https://github.com/chef/knife-ec-backup/pull/53) Refactor for improved testability and readability.
* [knife-ec-backup #51](https://github.com/chef/knife-ec-backup/pull/51) README: Document all current options, update description, remove stale sections.
* [knife-ec-backup #49](https://github.com/chef/knife-ec-backup/pull/49) Update knife-essential gem dependency.
* [knife-ec-backup #48](https://github.com/chef/knife-ec-backup/pull/48) Do not unnecessarily pull org objecsts when --only-org is passed.
* [knife-ec-backup #47](https://github.com/chef/knife-ec-backup/pull/47) Add explanatory comment to admin/billing-admin handling.
* [knife-ec-backup #44](https://github.com/chef/knife-ec-backup/pull/44) Ssd/common code first pass.
* [knife-ec-backup #43](https://github.com/chef/knife-ec-backup/pull/43) Use mixlib-cli to simplify webui_key config; cleanup whitespace.
* [knife-ec-backup #42](https://github.com/chef/knife-ec-backup/pull/42) Add Chef::Server class to handle version comparison logic.
* [knife-ec-backup #41](https://github.com/chef/knife-ec-backup/pull/41) Move all common options to an EcBase class.
* [knife-ec-backup #38](https://github.com/chef/knife-ec-backup/pull/38) Add sql configurable to backup and restore commands.
* [knife-ec-backup #36](https://github.com/chef/knife-ec-backup/pull/36) Fix group uploads by topologically sorting.
* [knife-ec-backup #34](https://github.com/chef/knife-ec-backup/pull/34) Use ChefFS from Chef 11.
* [knife-ec-backup #31](https://github.com/chef/knife-ec-backup/pull/31) Added support for backing up just a single org.
* [knife-ec-backup #30](https://github.com/chef/knife-ec-backup/pull/30) Ensure users are added to admins and billing-admins group.
* [knife-ec-backup #27](https://github.com/chef/knife-ec-backup/pull/27) Reset Chef::Config in org restore so it uses the pivotal key for the admins group.
* [knife-ec-backup #26](https://github.com/chef/knife-ec-backup/pull/26) Fixed bug where clients were added to groups before being created.
* [knife-ec-backup #25](https://github.com/chef/knife-ec-backup/pull/25) Add key import and key export commands.
* [knife-ec-backup #14](https://github.com/chef/knife-ec-backup/pull/14) Billing admin 403 error.
* [knife-ec-backup #12](https://github.com/chef/knife-ec-backup/pull/12) user_acl_rest is not initialized when it detects EC 11.0.1 or higher.
* [knife-ec-backup #10](https://github.com/chef/knife-ec-backup/pull/10) Fixed version number comparison
* [knife-ec-backup #09](https://github.com/chef/knife-ec-backup/pull/9) Fix for Older OPC version manifests use "Private Chef" instead of "private-chef" for the version number.
* [knife-ec-backup #04](https://github.com/chef/knife-ec-backup/pull/4) Removed billing-admins ACL download from full org download.
* [knife-ec-backup #03](https://github.com/chef/knife-ec-backup/pull/3) Updated Readme with more FAQ.
* [knife-ec-backup #02](https://github.com/chef/knife-ec-backup/pull/2) Fixed issues with Billing Admins Group ACL not being properly backed up.
