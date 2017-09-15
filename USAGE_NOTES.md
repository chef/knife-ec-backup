## Overview
`knife-ec-backup` is Chef's tool for migrating data between Chef server clusters of varying topologies (Standalone, Tier, old-HA, new-HA) and versions (with some limitations). Unlike Chef's filesystem-based backup/restore tools (`pg_dumpall` or `chef-server-ctl backup|restore`), it is going to be more flexible. Filesystem-based backup/restore tools should ONLY be used to backup/restore like versions AND like topologies of Chef Server. `knife-ec-backup` on the other hand, creates a portable object-based backup of the entire Chef server including all Orgs, Users, Cookbooks, Databags, ACLs etc.

Because Chef HA does not have an in-place migration tool, the expectation is that you will build and validate a new Chef HA Cluster and then migrate your data to it.

The steps to building a new Chef HA Cluster are as follows:

1. Build a new Chef HA Cluster (bonus points for using [aws_native_chef_server](https://github.com/chef-customers/aws_native_chef_server) to reproducibly build your cluster)
2. Validate your new Chef HA Cluster  (we cannot stress enough the importance of this)
    * Test each new frontend using `chef-server-ctl test`
    * Test both hard and soft failovers of the backend systems
    * Load test your new cluster using [chef-load](https://github.com/chef/chef-load)
3. Perform a full backup of your current production Chef Server cluster.  Note:
    * `knife-ec-backup` can generate considerable load on your cluster, particularly when increasing parallelism.
    * It is recommend that you upgrade to the latest versions of Chef Server if at all possible.   Using the latest version of `knife-ec-backup` is a requirement.
    * If you begin to experience 500 errors on your existing Chef Server during a full backup, attempt these during off-peak hours if possible.
    * Performance tuning of your Chef server may be required.  For more information see:
        * [Monitoring and Tuning your Chef Server](https://www.slideshare.net/AndrewDuFour1/monitoring-and-tuning-your-chef-server-chef-conf-talk)
        * [Tuning the Chef Server for Scale](http://irvingpop.github.io/blog/2015/04/20/tuning-the-chef-server-for-scale/)
        * [Understanding the Chef Server](https://www.youtube.com/watch?v=22GtVMHJDsI)
    * An advanced strategy may be to temporarily add a dedicated Frontend to existing Tier/HA topologies in order to reduce loading on the remaining frontends
4. Perform a full restore to the new cluster
    * IMPORTANT: Often, with old Chef Server data, there are data issues that new Chef Server versions will prevent from being loaded such as invalid user email addresses, missing ACL references, invalid cookbook fields etc. This will manifest itself if the form of errrors in the error report during and at the end of a `ec restore` operation. To correct these validation issues and allow the data to be uploaded to the new Chef Server, a knife-ec-backup companion tool exists named [knife-tidy](https://github.com/chef-customers/knife-tidy) Use it to clean up the object backup before attempting a restore operation.
    * The performance monitoring and tuning advice from the previous step will help achieve higher levels of parallelism
    * There may be errors encountered during restore - for example expired user-org invitations that point to deleted users.  It is recommended that you fix as many of these as possible on the source server.   If that's not possible, it's possible to fix the errors directly in the JSON filess as an intermediate "data cleanup" stage before restoring.
5. Validate the target cluster
    * Retest the cluster both `chef-server-ctl test` as well as re-pointing a number of non-critical nodes at the new cluster
6. Perform nightly incremental backups/restores
    * `knife-ec-backup` can operate in a pseudo-incremental mode as long as you keep the backup directory intact.  Continue to run backups/restores and you'll notice they complete much faster than the original
    * Note the time it takes for an incremental backup/restore to complete - this should provide you with the clearest guidance for how long of a downtime/maintenance window to schedule
    * An advanced strategy is to migrate one org or batches of orgs at a time.  In this case you'll need to:
        * Use the chef-client cookbook or similar strategy to update the client.rb file on every node to point at the new cluster
        * Filter already-migrated orgs from the backup/restore once migration is complete

### Initial Setup

It is recommended to install the latest version of `knife-ec-backup` from rubygems. However, if you're migrating from an old version of Chef Server though, you may not
be able to install the gem on your Chef Server due to the bundled ruby having library incompatibilities with the latest ec-backup gem.

Therefore, you should use a dedicated backup system other than your existing Chef Server with a high speed network connection.

On a dedicated backup system/workstation, install the [ChefDK](https://downloads.chef.io/chefdk) to get a ruby and chef-client library environment set up.
Be sure to check that the ChefDK binary path is before anything else in your $PATH, this way you will be sure to using the ChefDK ruby instead of a pre-existing
system ruby.

Next you are ready to install the latest knife-ec-backup gem from rubygems.org
```bash
chef gem install knife-ec-backup
```

Or install from master if you need the absolute latest:
```bash
git clone git@github.com:chef/knife-ec-backup.git
cd knife-ec-backup
chef gem build knife-ec-backup.gemspec
chef gem install knife-ec-backup*gem --no-ri --no-rdoc -V
```

Create a local backup working directory/folder and config file location
```bash
mkdir -p chef_backups/conf
```

Create a local `knife.rb` for the SOURCE and DESTINATION Chef Servers from which you will backup and restore.
Use a pre-existing Org
```bash
cd chef_backups/conf
cat <<EOF> knife_src_server.rb
current_dir = File.dirname(__FILE__)
log_level                :info
log_location             STDOUT
chef_server_url          "https://my.old-chef-server.com/organizations/brewinc"
ssl_verify_mode          :verify_peer
node_name                "pivotal"
client_key               "#{current_dir}/src_pivotal.pem"
EOF
cat <<EOF> knife_dst_server.rb
current_dir = File.dirname(__FILE__)
log_level                :info
log_location             STDOUT
chef_server_url          "https://my.new-chef-server.com/organizations/brewinc"
ssl_verify_mode          :verify_peer
node_name                "pivotal"
client_key               "#{current_dir}/dst_pivotal.pem"
EOF
```

Fetch the ssl certs

```bash
knife ssl -c knife_src_server.rb fetch
knife ssl -c knife_dst_server.rb fetch
```

Copy the `/etc/opscode/webui_priv.pem` file from both the SOURCE and DESTINATION Chef Servers locally into `chef_backups/conf` giving them unique names.

### Backup the Source

By default `knife-ec-backup` will use a concurrency of 10. You may consider bumping that up a little, to somewhere between 10 and 50.
You should watch the nginx access logs and opscode erchef logs on the Chef Server to ensure you are not overwhelming the server and forcing 503 Service Unavailable or 504 Gateway Timeout errors.

Keep a close watch on your Chef Server stats while running a backup and terminate the backup if returning excessive HTTP 50x to chef client agents.

The command below will download all data from the source Chef Server and store objects as individual json files beneath `chef_backups`. It is safe to re-run the backup multiple times over the existing `chef_backups` directory.  On subsequent runs, `knife-ec-backup` will do a differential backup of the `/cookbooks` objects.

```bash
knife ec backup chef_backups/ --webui-key chef_backups/conf/webui_priv_src.pem --concurrency 20 -c chef_backups/conf/knife_src_server.rb
```

**Note:** If using non-ldap users who need to login to manage console (Ask yourself why this is really necessary) then `--with-user-sql`, `--sql-user` (opscode_chef), `--sql-password` (from /etc/opscode/chef-server-running.json), `--sql-host` and `--sql-port` are required as well.

**Note:** Because the `backup` operation can be run multiple times. One good strategy may be to run repeated backups ahead of the migration day if the initial backup takes a prohibitively long time. Running several small backups ahead of time may be better than running one BIG one. Another supporting strategy might be performing backups during low-peak times, or adding frontend capacity during both backups (db connections) and restores (frontend CPU bound).

### Restore to the new Chef Server cluster

As mentioned earlier, the recommended strategy is to utilize a new destination cluster targeted for migration that has not been previously used. Easily spin new ones up with an [AWS Native Chef HA Cluster](https://github.com/chef-customers/aws_native_chef_server)

The command below will take the object based backup and restore it to a destination.

```bash
knife ec restore chef_backups/ --webui-key chef_backups/conf/webui_priv_dst.pem --concurrency 1 -c chef_backups/conf/knife_dst_server.rb
```

**IMPORTANT:** Unlike a backup operation, the concurrency needs to be set to 1 to avoid race conditions.

**Note:** Similar to the `backup` operation, same note about `--with-user-sql` potentially being required.

### Dealing With Errors
- If you encounter any un-recoverable errors during a backup/restore try adding the `-VV` flag to the knife command for maximum information.
