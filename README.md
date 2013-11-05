This product contains two knife commands:

    knife ec backup
    knife ec restore

They are intended to back up and restore an entire Enterprise Chef / Private Chef server, preserving the data in an intermediate, editable text format.

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
