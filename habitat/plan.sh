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
  echo "Unpacking from $PLAN_CONTEXT/../ to ${HAB_CACHE_SRC_PATH}/${pkg_dirname}"
  mkdir -p "${HAB_CACHE_SRC_PATH}/${pkg_dirname}"
  
  # Add verbose flag to see what's being copied
  rsync -av --exclude='.*' $PLAN_CONTEXT/../ ${HAB_CACHE_SRC_PATH}/${pkg_dirname}/
  
  echo "Contents after unpack:"
  ls -la "${HAB_CACHE_SRC_PATH}/${pkg_dirname}"
}

do_build() {
  pushd "${HAB_CACHE_SRC_PATH}/${pkg_dirname}" || exit 1
  
  # Check for essential files
  if [ ! -f "Gemfile" ]; then
    echo "Error: Gemfile not found"
    exit 1
  fi
  
  bundle install --jobs 2 --retry 5 --path ./vendor/bundle --binstubs --standalone
  popd
}

do_install() {
  pushd "${HAB_CACHE_SRC_PATH}/${pkg_dirname}" || exit 1
  
  echo "Contents of build directory:"
  ls -la
  
  echo "Copying files to $pkg_prefix/"
  cp -R . "$pkg_prefix/"
  
  echo "Contents of $pkg_prefix after copy:"
  ls -la "$pkg_prefix/"
  
  # Check for broken symlinks or problematic files
  echo "Checking for broken symlinks in $pkg_prefix:"
  find "$pkg_prefix" -type l -exec test ! -e {} \; -print
  
  # Check permissions
  echo "Checking file permissions in bin and lib directories:"
  if [ -d "$pkg_prefix/bin" ]; then
    ls -la "$pkg_prefix/bin/"
  fi
  if [ -d "$pkg_prefix/lib" ]; then
    ls -la "$pkg_prefix/lib/"
  fi
  
  # Remove unnecessary files that might cause issues
  echo "Cleaning up unnecessary files:"
  rm -rf "$pkg_prefix/spec" "$pkg_prefix/test" "$pkg_prefix/.bundle" "$pkg_prefix/results"
  
  # Ensure bin directory has executable files
  if [ -d "$pkg_prefix/bin" ]; then
    chmod +x "$pkg_prefix/bin"/*
  fi
  
  if [ -f "$pkg_prefix/bin/knife" ]; then
    fix_interpreter "$pkg_prefix/bin/knife" core/coreutils bin/env
  else
    echo "Warning: $pkg_prefix/bin/knife not found"
  fi
  
  # Final verification
  echo "Final package contents:"
  find "$pkg_prefix" -type f -exec ls -la {} \; | head -20

  echo "Checking for zero-length files:"
  find "$pkg_prefix" -type f -empty -print

  echo "Testing manual blake2b hash generation:"
  find "$pkg_prefix" -type f -exec blake2bsum {} \; | head -10
  
  popd
}

pkg_version() {
  cat "$PLAN_CONTEXT/../VERSION"
}

do_before() {
  echo "PLAN_CONTEXT: $PLAN_CONTEXT"
  echo "Looking for VERSION file at: $PLAN_CONTEXT/../VERSION"
  ls -la "$PLAN_CONTEXT/../"
  
  if [ ! -f "$PLAN_CONTEXT/../VERSION" ]; then
    exit_with "Cannot find VERSION file! You must enter the studio from the project's top-level directory." 56
  fi
  update_pkg_version
}
