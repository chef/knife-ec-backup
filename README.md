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

This knife plugin requires Chef 11.8+.

## Chef 10

Users who are still using Chef 10 can use the most recent 1.x version
of this gem.  Version 1.x additionally depends on knife-essentials.

# Installation

## Chef Server Install (Recommended)
This will install the plugin directly on the Chef Server:

    /opt/opscode/embedded/bin/gem install knife-ec-backup

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

## knife ec backup DEST_DIR (options)

*Options*

  * `--webui-key`:
    Used to set the path to the WebUI Key (default: /etc/opscode/webui_priv.pem)
  * `--skip-useracl`:
    Whether to skip downloading User ACLs.  This is required for EC 11.0.0 and lower (default: false)
  * `--skip-version-check'`:
    Whether to skip checking the Chef Server version.  This will also skip any auto-configured options (default: false)

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

*Options*

  * `--webui-key`:
    Used to set the path to the WebUI Key (default: /etc/opscode/webui_priv.pem)
  * `--overwrite-pivotal`:
    Whether to overwrite pivotal's key.  Once this is done, future requests will fail until you fix the private key (default: false)
  * `--skip-useracl`:
    Whether to skip downloading User ACLs.  This is required for EC 11.0.0 and lower (default: false)
  * `--skip-version-check'`:
    Whether to skip checking the Chef Server version.  This will also skip any auto-configured options (default: false)

Restores all data from a repository to an Enterprise Chef / Private Chef server.

# TODO

* Ensure easy installation into embedded ruby gemset on Chef Server.
* Remove requirement for Knife Essentials gem to be installed.
* Single org backups.
* This plugin does **NOT** currently backup user passwords.  **They will have to be reset after a restore.**
* This plugin does **NOT** currently restore user public keys.  **Private keys will have to be reset after a restore.**
* This plugin does **NOT** currently restore custom user ACLs.  **It will revert back to default ACLs on a restore.**
