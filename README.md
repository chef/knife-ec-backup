# knife EC backup

# Description

This is an UNOFFICIAL and EXPERIMENTAL knife plugin intended to back up and restore an entire Enterprise Chef / Private Chef server, preserving the data in an intermediate, editable text format.

# Requirements

This knife plugin currently requires the Knife-Essentials gem to be installed in the same gemset. This requirement is currently hosted here:

    https://github.com/jkeiser/knife-essentials

# Installation

This knife plugin is packaged as a gem.  To install it, clone the
git repository and run the following:

    gem build knife-ec-backup.gemspec
    gem install knife-ec-backup-1.0.0.gem

# Configuration

## Permissions
Note that users in an EC installation lack the permissions to pull all of the data from all organizations and other users.
This plugin **REQUIRES THE PIVOTAL KEY AND WEBUI KEY** from the Chef Server
If you are not running this from the Chef Server, you can use --user and --key to pass the pivotal information along.

## knife.rb
Unlike other knife subcommands the subcommands in the knife-ec-backup plugin make API calls against the root of your EC installations API endpoint.

Typically the chef_server_url for your OPC installation may look like this:

    chef_server_url https://chef.yourdomain.com/organizations/ORGNAME

To configure knife-ec-backup, set the `chef_server_root` option to the root of your OPC installation:

    chef_server_root https://chef.yourdomain.com/

# Subcommands

## knife ec backup DEST_DIR WEBUI_KEY \[USER_ACL_REST\] (options)

*Options*

  * `--concurrency`:
    Maximum number of simultaneous requests to send (default: 10)
  * `--skip-useracl`:
    Whether to skip downloading User ACLs.  This is required for EC 11.0.0 and lower (default: false)

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

## knife ec restore DEST_DIR WEBUI_KEY \[USER_ACL_REST\] (options)

*Options*

  * `--concurrency`:
    Maximum number of simultaneous requests to send (default: 10)
  * `--overwrite-pivotal`:
    Whether to overwrite pivotal's key.  Once this is done, future requests will fail until you fix the private key (default: false)
  * `--skip-useracl`:
    Whether to skip downloading User ACLs.  This is required for EC 11.0.0 and lower (default: false)

Restores all data from a repository to an Enterprise Chef / Private Chef server.

# TODO

* Ensure easy installation into embedded ruby gemset on Chef Server.
* Remove requirement for Knife Essentials gem to be installed.
* Auto detect Chef Server version and auto apply necessary options (with option to disable auto check+auto apply)
* Check if /etc/opscode/webui_priv.pem is present
* This plugin does **NOT** currently backup user passwords.  **They will have to be reset after a restore.**