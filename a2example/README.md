# Restore Backup from Standalone Chef Infra Server to Automate2 Server with Embedded Infra server

- the Postgre DB in this sample is embedded, but with tweaks, it will work with an external PostgreSQL server. 
- The examples here use an Automate2 server created in Vagrant. This is an excellent way to rehearse and validate without affecting production systems.

> Before you begin this phase: read blog post on `knife-ec-backup` and `knife-tidy` by Irving Popovetsky 
> <https://blog.chef.io/migrating-chef-server-knife-ec-backup-knife-tidy/>
> This information contains multiple additional options to help guide you for your situation.

## Prepare your A2 Server

The Vagrantfile makes an Ubuntu 18.04 Automate2 server with the hostname *learn-chef.auto* and connects it to a private network with the ip address 192.168.33.199. Add this to your local hosts file to allow connecting using a browser.

1. Stage your folder from the `knife-ec-backup`

    copy the folder created from running `knife ec backup` into the `vagrantA2` folder, the Vagrantfile specifies to sync contents in this directory to `/opt/a2-testing`

1. Stand up test Automate Server using Vagrant

    open a new shell, `cd vagrantA2; vagrant up` go get a ☕ as this will take a couple minutes.
    once vagrant finishes, log in using `vagrant ssh`

1. Install workstation on the Vagrant A2 Server

    `wget https://packages.chef.io/files/stable/chef-workstation/20.9.158/ubuntu/18.04/chef-workstation_20.9.158-1_amd64.deb`
    `sudo dpkg -i chef-workstation_20.9.158-1_amd64.deb`

1. Install development tools and libpq-dev

    `sudo apt-get install -y gcc libpq-dev`

1. Install the `chef-ec-backup` gem

    `chef gem install knife-ec-backup`


## Prepare Automate2 to restore

1. Use `knife-tidy` to Clean up your Backup Files (optional)

1. Dry Run and Restore

    `sudo /opt/chef-workstation/bin/knife ec restore /opt/a2-testing/<ec-backup directory>  -s https://learn-chef.auto --sql-db automate-cs-oc-erchef -u pivotal --webui-key /hab/svc/automate-cs-oc-erchef/data/webui_priv.pem -V --dry-run`

    remove the `--dry-run` argument to actually perform the restore. 


## Validate your Automate2

1. Put a copy of your .chef folder from your workstation onto the Vagrant A2 server

    > ⚠️ PLEASE be CAREFUL: understand that at this point your `knife.rb` to points to your current **Chef Infra server**. ⚠️

1. Edit your `knife.rb`
    change the `chef_server_url` to point to *learn-chef.auto*

1. Get your "fake" certs

    `/opt/chef-workstation/bin/knife ssl fetch`

1. Validate your System and adjust as needed

    - count the cookbooks, envirionments, data_bags etc on the A2 server and compare against what you have in production.

## Make the Plan for the Actual Restore

Vagrant makes it easy to rehearse and try things out before doing the actual work.
