# knife-ec-backup Change Log

<!-- latest_release 3.0.6 -->
## [v3.0.6](https://github.com/chef/knife-ec-backup/tree/v3.0.6) (2025-09-24)

#### Merged Pull Requests
- [CHEF-21785][CHEF-21788] Updated the restore method to preserve the frozen cookbook status [#188](https://github.com/chef/knife-ec-backup/pull/188) ([ashiqueps](https://github.com/ashiqueps))
<!-- latest_release -->

<!-- release_rollup since=3.0.5 -->
### Changes not yet released to rubygems.org

#### Merged Pull Requests
- [CHEF-21785][CHEF-21788] Updated the restore method to preserve the frozen cookbook status [#188](https://github.com/chef/knife-ec-backup/pull/188) ([ashiqueps](https://github.com/ashiqueps)) <!-- 3.0.6 -->
<!-- release_rollup -->

<!-- latest_stable_release -->
## [v3.0.5](https://github.com/chef/knife-ec-backup/tree/v3.0.5) (2025-08-19)

#### Merged Pull Requests
- upgrade ruby to v3.1 [#180](https://github.com/chef/knife-ec-backup/pull/180) ([timin](https://github.com/timin))
- remove deprecated exists? for exist? [#183](https://github.com/chef/knife-ec-backup/pull/183) ([Stromweld](https://github.com/Stromweld))
- CHEF-24921 – Added support to build and test against LTS2024 channel and promoting package to LTS2024-current channel [#187](https://github.com/chef/knife-ec-backup/pull/187) ([nikhil2611](https://github.com/nikhil2611))
- CHEF-23857 - Security fixes and testing with ruby 3.1.7 [#186](https://github.com/chef/knife-ec-backup/pull/186) ([nikhil2611](https://github.com/nikhil2611))
<!-- latest_stable_release -->

## [v3.0.1](https://github.com/chef/knife-ec-backup/tree/v3.0.1) (2022-10-26)

#### Merged Pull Requests
- Updated code owners to current teams [#173](https://github.com/chef/knife-ec-backup/pull/173) ([vkarve-chef](https://github.com/vkarve-chef))

## [v3.0.0](https://github.com/chef/knife-ec-backup/tree/v3.0.0) (2022-01-27)

#### Merged Pull Requests
- Delete node and client ALCs on --purge option. [#171](https://github.com/chef/knife-ec-backup/pull/171) ([lbakerchef](https://github.com/lbakerchef))

## [v2.5.3](https://github.com/chef/knife-ec-backup/tree/v2.5.3) (2021-10-13)

#### Merged Pull Requests
- Upgrade to GitHub-native Dependabot [#156](https://github.com/chef/knife-ec-backup/pull/156) ([dependabot-preview[bot]](https://github.com/dependabot-preview[bot]))
- Fix CI bundle install [#163](https://github.com/chef/knife-ec-backup/pull/163) ([jasonwbarnett](https://github.com/jasonwbarnett))
- Require Ruby 2.6 or later [#165](https://github.com/chef/knife-ec-backup/pull/165) ([tas50](https://github.com/tas50))
- Update to Sequel 5.9.0 [#164](https://github.com/chef/knife-ec-backup/pull/164) ([lbakerchef](https://github.com/lbakerchef))
- Fix uninitialized constant Net::HTTPServerException [#166](https://github.com/chef/knife-ec-backup/pull/166) ([lbakerchef](https://github.com/lbakerchef))
- Gracefully handle missing parallelizer in Chef 17 [#158](https://github.com/chef/knife-ec-backup/pull/158) ([jasonwbarnett](https://github.com/jasonwbarnett))

## [v2.4.15](https://github.com/chef/knife-ec-backup/tree/v2.4.15) (2021-04-21)

#### Merged Pull Requests
- Add support to use the automate chef server [#138](https://github.com/chef/knife-ec-backup/pull/138) ([jaym](https://github.com/jaym))
- Update Chef -&gt; Chef Infra, add note on postgresql [#146](https://github.com/chef/knife-ec-backup/pull/146) ([btm](https://github.com/btm))
- Fix the gemspec license value to be a valid value [#155](https://github.com/chef/knife-ec-backup/pull/155) ([tas50](https://github.com/tas50))

## [v2.4.12](https://github.com/chef/knife-ec-backup/tree/v2.4.12) (2020-08-21)

#### Merged Pull Requests
- Fix habitat package [#137](https://github.com/chef/knife-ec-backup/pull/137) ([jaym](https://github.com/jaym))
- Fix the tests [#139](https://github.com/chef/knife-ec-backup/pull/139) ([jaym](https://github.com/jaym))
- Fix minor spelling mistakes [#140](https://github.com/chef/knife-ec-backup/pull/140) ([tas50](https://github.com/tas50))
- Optimize our requires [#142](https://github.com/chef/knife-ec-backup/pull/142) ([tas50](https://github.com/tas50))
- Pin simplecov to fix Ruby 2.4 tests [#143](https://github.com/chef/knife-ec-backup/pull/143) ([tas50](https://github.com/tas50))

## [v2.4.7](https://github.com/chef/knife-ec-backup/tree/v2.4.7) (2020-04-19)

#### Merged Pull Requests
- ability to log errors in separate directory [#135](https://github.com/chef/knife-ec-backup/pull/135) ([jeremymv2](https://github.com/jeremymv2))

## [v2.4.6](https://github.com/chef/knife-ec-backup/tree/v2.4.6) (2019-12-30)

#### Merged Pull Requests
- Jjh/add hab plan [#131](https://github.com/chef/knife-ec-backup/pull/131) ([itmustbejj](https://github.com/itmustbejj))
- Substitute require for require_relative [#132](https://github.com/chef/knife-ec-backup/pull/132) ([tas50](https://github.com/tas50))
- Convert PR testing to Buildkite [#133](https://github.com/chef/knife-ec-backup/pull/133) ([tas50](https://github.com/tas50))

## [v2.4.3](https://github.com/chef/knife-ec-backup/tree/v2.4.3) (2019-08-19)

#### Merged Pull Requests
- Added support for Expeditor [#127](https://github.com/chef/knife-ec-backup/pull/127) ([vijaymmali1990](https://github.com/vijaymmali1990))
- enable backup/restore via Chef Automate Chef Server API [#128](https://github.com/chef/knife-ec-backup/pull/128) ([jeremymv2](https://github.com/jeremymv2))
- Update README.md as per Chef OSS Best Practices [#130](https://github.com/chef/knife-ec-backup/pull/130) ([vsingh-msys](https://github.com/vsingh-msys))