pkg_name=knife-ec-backup
pkg_origin=chef
pkg_maintainer="The Habitat Maintainers <humans@habitat.sh>"
pkg_description="A knife plugin for backup/restore of Chef Infra Server data."
pkg_upstream_url="https://github.com/chef/knife-ec-backup"
pkg_license=('Apache-2.0')
pkg_bin_dirs=(bin)
pkg_lib_dirs=(lib)
pkg_svc_user=root
pkg_svc_group=${pkg_svc_user}
ruby_pkg=$([ "$HAB_BLDR_CHANNEL" == "LTS-2024" ] && echo core/ruby3_1 || echo core/ruby31)
postgresql_package=$([ "$HAB_BLDR_CHANNEL" == "LTS-2024" ] && echo core/postgresql13-client || echo core/postgresql-client)
echo "Using Ruby package: $ruby_pkg"

pkg_build_deps=(
  core/gcc-libs
  core/git
  core/make
  core/openssl
  core/rsync
)
pkg_deps=(
  core/coreutils
  core/gcc
  "$ruby_pkg"
  "$postgresql_package"
  core/libffi
)

do_unpack() {
  mkdir -p "${HAB_CACHE_SRC_PATH}/${pkg_dirname}"
  rsync -a --exclude='.*' --exclude='results/' "$PLAN_CONTEXT/../" "${HAB_CACHE_SRC_PATH}/${pkg_dirname}/"
}

do_build() {
  pushd "${HAB_CACHE_SRC_PATH}/${pkg_dirname}" || exit 1
  bundle install --jobs 2 --retry 5 --path ./vendor/bundle --binstubs --standalone
  popd
}

do_install() {
  pushd "${HAB_CACHE_SRC_PATH}/${pkg_dirname}" || exit 1
  cp -R . "$pkg_prefix/"
  fix_interpreter "$pkg_prefix/bin/knife" core/coreutils bin/env
  popd
}

pkg_version() {
  cat "$PLAN_CONTEXT/../VERSION"
}

do_before() {
  if [ ! -f "$PLAN_CONTEXT/../VERSION" ]; then
    exit_with "Cannot find VERSION file! You must enter the studio from the project's top-level directory." 56
  fi
  update_pkg_version
}
