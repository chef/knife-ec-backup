pkg_name=knife-ec-backup
pkg_origin=itmustbejj
#pkg_origin=chef
pkg_maintainer="The Habitat Maintainers <humans@habitat.sh>"
#pkg_description="A monitoring framework that aims to be simple, malleable, and scalable."
#pkg_upstream_url="https://sensuapp.org"
#pkg_license=('MIT')
pkg_bin_dirs=(bin)
pkg_lib_dirs=(lib)
pkg_svc_user=root
pkg_svc_group=${pkg_svc_user}
pkg_build_deps=(
  core/gcc-libs
  core/libffi
  core/make
  core/openssl
)
pkg_deps=(
  core/bundler
  core/coreutils
  core/gcc
  core/ruby
)

pkg_build_deps=(
  core/git
  core/make
  core/postgresql-client
)

do_unpack() {
  mkdir -p "${HAB_CACHE_SRC_PATH}/${pkg_dirname}"
  cp -r ../* ${HAB_CACHE_SRC_PATH}/${pkg_dirname}/
}


do_build() {
  pushd "${HAB_CACHE_SRC_PATH}/${pkg_dirname}"
  bundle install --jobs 2 --retry 5 --path ./vendor/bundle --binstubs
  popd
}

do_install() {
  pushd "${HAB_CACHE_SRC_PATH}/${pkg_dirname}"
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

