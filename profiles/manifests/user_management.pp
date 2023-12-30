class profile::user_management {
  # Retrieve user names from the configuration file
  $users = lookup('users_and_keys').keys

  # Loop through the user names
  each($users) |$user| {
    user { $user:
      ensure     => 'present',
      shell      => '/bin/bash',
      home       => "/home/${user}",
      managehome => true,
      groups     => ['root', 'odoo_group'],
    }

    file { "/home/${user}/.ssh":
      ensure  => 'directory',
      owner   => $user,
      group   => $user,
      mode    => '0700',
    }

    file { "/home/${user}/.ssh/authorized_keys":
      ensure  => 'file',
      owner   => $user,
      group   => $user,
      mode    => '0600',
      content => file("puppet:///modules/puppet_odoo/files/${user}.pub"),
    }
  }
}

