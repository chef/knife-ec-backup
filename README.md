# knife EC backup

# Description

knife-ec-backup can backup and restore the data in an Enterprise Chef
Server installation, preserving the data in an intermediate, editable
text format.  It is similar to the `knife download` and `knife upload`
commands and uses the same underlying libraries, but also includes
workarounds for objects not yet supported by those tools and various
Server API deficiencies.  The long-run goal is to improve `knife
donwload`, `knife upload` and the Chef Server API and deprecate this
tool.

# Requirements

This knife plugin requires Chef Client 11.8+.

## Chef 10

Users who are still using Chef 10 can use the most recent 1.x version
of this gem.  Version 1.x additionally depends on knife-essentials.

## Server Support

This plugin currently supports Enterprise Chef 11 and Chef Server 12.
Support for the beta key rotation features is provided via the
`--with-keys-sql` flag, but users of this feature should note that
this may change once the Chef Server supports an API-based export of
the key data.

# Installation

## Chef Server Install (Recommended)
This will install the plugin directly on the Chef Server:

    /opt/opscode/embedded/bin/gem install knife-ec-backup

The latest versions of knife-ec-backup require gems with native
extensions, thus you must install a standard build toolchain.  To
install knife-ec-backup without installing libpq development headers
on your system, try the following:

   /opt/opscode/embedded/bin/gem install knife-ec-backup -- --with-pg-config=/opt/opscode/embedded/postgresql/9.2/bin/pg_config

## Build from source
Clone the git repository and run the following from inside:

    gem build knife-ec-backup.gemspec
    gem install knife-ec-backup-1.1.3.gem

# Configuration

## Permissions

Note that most users in an EC installation lack the permissions to pull all of the data from all organizations and other users.
This plugin **REQUIRES THE PIVOTAL KEY AND WEBUI KEY** from the Chef Server.
It is recommended that you run this from a frontend Enterprise Chef Server, you can use --user and --key to pass the pivotal information along.

# Subcommands

## Common Option

The following options are supported across all subcommands:

  * `--sql-host`:
    The hostname of the Chef Server's postgresql server. (default: localhost)

  * `--sql-port`:
    The postgresql listening port on the Chef Server. (default: 5432)

  * `--sql-user`:
    The username of postgresql user with access to the opscode_chef
    database. (default: autoconfigured from
    /etc/opscode/chef-server-running.json)

  * `--sql-password`:
    The password for the sql_user.  (default: autoconfigured from /etc/opscode/chef-server-running.json)

## knife ec backup DEST_DIR (options)

*Options*

  * `--concurrency THREAD_COUNT`:
    The maximum number of concurrent requests to make to the Chef
    Server. (default: 10)

  * `--webui-key`:
    Used to set the path to the WebUI Key (default: /etc/opscode/webui_priv.pem)
    skip any auto-configured options (default: false)

  * `--with-user-sql`:
    Whether to backup/restore user data directly from the database.  This
    requires access to the listening postgresql port on the Chef
    Server.  This is required to correctly handle user passwords and
    to ensure user-specific association groups are not duplicated.

  * `--with-key-sql`: Whether to backup/restore key data directly
    from the database.  This requires access to the listening
    postgresql port on the Chef Server.  This is required to correctly
    handle keys in Chef Servers with multikey support. This option
    will only work on `restore` if it was also used during the
    `backup`.

  * `--skip-useracl`:
    Skip download/restore of the user ACLs.  User ACLs are the
    permissions that actors have *on other global users*.  These are
    not the ACLs that control what permissions users have on various
    Chef objects.

  * `--skip-version-check`:
    Skip Chef Server version check. This will also skip any auto-configured options (default: false)

  * `--only-org ORG`:
    Only donwload/restore objects in the named organization. Global
    objects such as users will still be downloaded/restored.

Creates a repository of an entire Enterprise Chef / Private Chef server.

The format of the repository is based on the `knife-essentials` (`knife download`) format and looks like this:

    users
      <name>.json
    user_acls
      <name>.json
    organizations
      <orgname>
        acls
          <type>
            <name>.json
        clients
          <name>.json
        containers
          <name>.json
        cookbooks
          <name>-<version>
        data_bags
          <bag name>
            <item name>
        environments
          <name>.json
        groups
          <name>.json
        nodes
          <name>.json
        roles
          <name>.json
        org.json
        members.json
        invitations.json

This compares very closely with the "knife download /" from an OSC server:

    clients
      <name>.json
    cookbooks
      <name>-<version>
    data_bags
      <bag name>
        <item name>
    environments
      <name>.json
    nodes
      <name>.json
    roles
      <name>.json
    users
      <name>.json>

## knife ec restore DEST_DIR (options)

Restores all data from the specified DEST_DIR to an Enterprise Chef /
Private Chef server. DEST_DIR should be a backup directory created by
`knife ec backup`

*Options*

  * `--webui-key`:
    Used to set the path to the WebUI Key (default: /etc/opscode/webui_priv.pem)

  * `--overwrite-pivotal`:
    Whether to overwrite pivotal's key.  Once this is done, future
    requests will fail until you fix the private key (default: false)

  * `--skip-users`:
    Skip the restore of global users.  This may cause organization
    uploading to fail if the necessary users do not exist on the Chef
    Server.

  * `--concurrency THREAD_COUNT`:
    The maximum number of concurrent requests to make to the Chef
    Server. (default: 10)

  * `--skip-version-check`:
    Skip Chef Server version check. This will
    also skip any auto-configured options (default: false)

  * `--with-user-sql`:
    Whether to backup/restore user data directly from the database.  This
    requires access to the listening postgresql port on the Chef
    Server.  This is required to correctly handle user passwords and
    to ensure user-specific association groups are not
    duplicated. This option will only work on `restore` if it was also
    used during the `backup`.

  * `--with-key-sql`: Whether to backup/restore key data directly
    from the database.  This requires access to the listening
    postgresql port on the Chef Server.  This is required to correctly
    handle keys in Chef Servers with multikey support. This option
    will only work on `restore` if it was also used during the
    `backup`.

  * `--skip-useracl`:
    Skip download/restore of the user ACLs.  User ACLs are the
    permissions that actors have *on other global users*.  These are
    not the ACLs that control what permissions users have on various
    Chef objects.

  * `--only-org ORG`:
    Only donwload/restore objects in the named organization. Global
    objects such as users will still be downloaded/restored.

## knife ec key export [FILENAME]

Create a json representation of the users table from the Chef Server
database.  If no argument is given, the name of the backup is
`key_dump.json`.

Please note, most users should use `knife ec backup` with the
`--with-user-sql` option rather than this command.

## knife ec key import [FILENAME]

Import a json representation of the users table from FILENAME to the
the Chef Server database.  If no argument is given, the filename is
assumed to be `key_dump.json`.

Please note, most user should use `knife ec restore` with the
`--with-user-sql` option rather than this command.

# Known Bugs

- knife-ec-backup cannot be installed in the embedded gemset of Chef
  Server 12.  This will be resolved in a future Chef Server release.

- `knife ec restore` can fail to restore cookbooks, failing with an
  internal server error. A common cause of this problem is a
  concurrency bug in Chef Server. Setting `--concurrency 1` can often
  work around the issue.

- `knife ec restore` can fail if the pool of pre-created organizations
  can not keep up with the newly created organizations.  This can
  typically be resolved simply be restarting the restore.  To avoid
  this error for backups with large number of organizations, try
  setting (in /etc/opscode/private-chef.rb):

        opscode_org_creator['ready_org_depth']

  to the number of organizations in your backup and waiting for the
  pool to fill before running `knife ec restore`
