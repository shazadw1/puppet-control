class profile::odoo {
  # Retrieve and process variables from config.yml
  $odoo_version_full = lookup('odoo_version')
  $odoo_version = regsubst($odoo_version_full, '\.0$', '') # Removes .0 from the version
  $odoo_user = "odoo${odoo_version}"
  $pg_username = "odoo${odoo_version}"
  $pg_password = "odoo${odoo_version}"

  # Ensure the required packages are installed
  package { [
    'openssh-server',
    'fail2ban',
    'python3-pip',
    'python-dev',
    'python3-dev',
    'libxml2-dev',
    'libxslt1-dev',
    'zlib1g-dev',
    'libsasl2-dev',
    'libldap2-dev',
    'build-essential',
    'libssl-dev',
    'libffi-dev',
    'libmysqlclient-dev',
    'libjpeg-dev',
    'libpq-dev',
    'libjpeg8-dev',
    'liblcms2-dev',
    'libblas-dev',
    'libatlas-base-dev',
    'npm',
  ]:
    ensure => installed,
  }

  # Create a symbolic link for 'nodejs' to 'node'
  exec { 'create-nodejs-symlink':
    command => 'sudo ln -s /usr/bin/nodejs /usr/bin/node',
    creates => '/usr/bin/node',
    path    => ['/bin', '/usr/bin'],
  }

  # Install required npm packages
  exec { 'install-npm-packages':
    command => 'sudo npm install -g less less-plugin-clean-css',
    path    => ['/bin', '/usr/bin'],
    require => Exec['create-nodejs-symlink'],
  }

  # Install PostgreSQL
  package { 'postgresql':
    ensure => installed,
  }

  # Ensure PostgreSQL is installed and running
  service { 'postgresql':
    ensure    => 'running',
    enable    => true,
    subscribe => Package['postgresql'],
  }

  # Switch to the 'postgres' user and create a PostgreSQL user
  exec { 'create-postgres-user':
    command => "sudo su - postgres -c 'createuser --createdb --username postgres --no-createrole --no-superuser --pwprompt ${pg_username}'",
    path    => ['/bin', '/usr/bin'],
    creates => "/var/lib/postgresql/${pg_username}",
    require => [
      Package['postgresql'],
      Service['postgresql'],
    ],
  }

  # Set the password for the PostgreSQL user
  exec { 'set-postgres-password':
    command => "sudo su - postgres -c 'psql -c \"ALTER USER ${pg_username} WITH SUPERUSER;\"'",
    path    => ['/bin', '/usr/bin'],
    unless  => "sudo su - postgres -c 'psql -c \"SELECT 1 FROM pg_roles WHERE rolname = ''${pg_username}'';\"' | grep -q 1",
    require => [
      Package['postgresql'],
      Service['postgresql'],
    ],
  }

  # Download and install wkhtmltopdf
  exec { 'download-wkhtmltopdf':
    command => 'sudo wget https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.bionic_amd64.deb',
    cwd     => '/tmp',
    creates => '/tmp/wkhtmltox_0.12.5-1.bionic_amd64.deb',
    path    => ['/bin', '/usr/bin'],
  }

  exec { 'install-wkhtmltopdf':
    command => 'sudo dpkg -i wkhtmltox_0.12.5-1.bionic_amd64.deb && sudo apt install -f',
    cwd     => '/tmp',
    require => Exec['download-wkhtmltopdf'],
  }

# Create the system user for Odoo
  user { $odoo_user:
    ensure => 'system',
    home   => "/opt/${odoo_user}",
    shell  => '/bin/bash',
    require => Package['python3-pip'],
  }

  # Add the Odoo system user to the odoo_group
  group { 'odoo_group':
    ensure => 'present',
  }

  # Set the primary group for the Odoo system user to odoo_group
  user { $odoo_user:
    gid => 'odoo_group',
  }

  # Set the public key for the Odoo system user
  file { "/opt/${odoo_user}/.ssh/authorized_keys":
    ensure  => file,
    owner   => $odoo_user,
    group   => 'odoo_group',
    mode    => '0644',
    source  => "puppet:///modules/puppet_odoo/keys/${odoo_user}.pub",
    require => User[$odoo_user],
  }



  # Switch to the Odoo user and clone the Odoo repository
  exec { "git-clone-odoo-${odoo_version}":
    command => "sudo su - ${odoo_user} -s /bin/bash -c 'git clone https://www.github.com/odoo/odoo --depth 1 --branch ${odoo_version} --single-branch .'",
    path    => ['/bin', '/usr/bin'],
    creates => "/opt/${odoo_user}/odoo",
    require => Package['git'],
  }

  # Install Python dependencies for Odoo
  exec { "pip-install-odoo-requirements-${odoo_version}":
    command => "sudo pip3 install -r /opt/${odoo_user}/requirements.txt",
    path    => ['/bin', '/usr/bin'],
    creates => "/opt/${odoo_user}/.pip",
    require => Exec["git-clone-odoo-${odoo_version}"],
  }

  # Create the Odoo configuration file
  file { "/etc/${odoo_user}.conf":
    ensure  => file,
    owner   => $odoo_user,
    group   => $odoo_user,
    mode    => '0640',
    content => template('puppet_odoo/odoo.conf.erb'),
    require => Package['odoo'],
  }

  # Ensure the /var/log/odoo directory exists
  file { '/var/log/odoo':
    ensure => directory,
    owner  => $odoo_user,
    group  => 'root',
    mode   => '0755',
    require => User[$odoo_user],
  }

  # Create the Odoo service file from the template
  file { "/etc/systemd/system/${odoo_user}.service":
    ensure  => file,
    content => template('puppet_odoo/odoo17.service.erb'),
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    notify  => Exec['reload-systemd-daemon'],
  }

  # Reload systemd daemon to pick up the new service file
  exec { 'reload-systemd-daemon':
    command     => 'systemctl daemon-reload',
    path        => ['/bin', '/usr/bin'],
    refreshonly => true,
  }

  # Enable the Odoo service
  exec { "enable-${odoo_user}-service":
    command => "systemctl enable ${odoo_user}.service",
    path    => ['/bin', '/usr/bin'],
    require => File["/etc/systemd/system/${odoo_user}.service"],
    unless  => "systemctl is-enabled ${odoo_user}.service | grep enabled",
  }

  # Add a sudoers rule for odoo_user to control the odoo service
  file { "/etc/sudoers.d/${odoo_user}":
    ensure  => file,
    content => "${odoo_user} ALL=(root) NOPASSWD: /bin/systemctl start ${odoo_user}.service, /bin/systemctl stop ${odoo_user}.service, /bin/systemctl restart ${odoo_user}.service\n",
    owner   => 'root',
    group   => 'root',
    mode    => '0440',
    require => User[$odoo_user],
  }

  # ... [rest of the code] ...
}

  # Odoo-specific package installation
  package { [ 'python3-pip', 'python-dev', 'python3-dev', 'libxml2-dev', ... ]:
    ensure => installed,
  }

  # Node.js setup
  exec { 'create-nodejs-symlink': ... }
  exec { 'install-npm-packages': ... }

  # PostgreSQL setup
  class { 'postgresql::server': } # Using the puppetlabs-postgresql module
  postgresql::server::role { $pg_username: password_hash => postgresql_password($pg_username, $pg_password) }

  # Odoo user and group setup
  user { $odoo_user: ... }
  group { 'odoo_group': ... }
  User[$odoo_user] -> Group['odoo_group']

  # SSH key setup for Odoo user
  file { "/opt/${odoo_user}/.ssh/authorized_keys": ... }

  # Git, Odoo clone, Python dependencies
  package { 'git': ... }
  exec { "git-clone-odoo-${odoo_version}": ... }
  exec { "pip-install-odoo-requirements-${odoo_version}": ... }

  # Odoo configuration file
  file { "/etc/${odoo_user}.conf":
    ensure  => file,
    owner   => $odoo_user,
    group   => $odoo_user,
    mode    => '0640',
    content => template('puppet_odoo/odoo.conf.erb'),
  }

  # Odoo service file from template
  file { "/etc/systemd/system/${odoo_user}.service":
    ensure  => file,
    content => template('puppet_odoo/odoo.service.erb'),
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    notify  => Exec['reload-systemd-daemon'],
  }

  # Reload systemd daemon to pick up the new service file
  exec { 'reload-systemd-daemon':
    command     => 'systemctl daemon-reload',
    path        => ['/bin', '/usr/bin'],
    refreshonly => true,
  }

  # Enable the Odoo service
  exec { "enable-${odoo_user}-service":
    command => "systemctl enable ${odoo_user}.service",
    path    => ['/bin', '/usr/bin'],
    require => File["/etc/systemd/system/${odoo_user}.service"],
    unless  => "systemctl is-enabled ${odoo_user}.service | grep enabled",
  }

  # Add a sudoers rule for odoo_user to control the odoo service
  file { "/etc/sudoers.d/${odoo_user}":
    ensure  => file,
    content => "${odoo_user} ALL=(root) NOPASSWD: /bin/systemctl start ${odoo_user}.service, /bin/systemctl stop ${odoo_user}.service, /bin/systemctl restart ${odoo_user}.service\n",
    owner   => 'root',
    group   => 'root',
    mode    => '0440',
  }

  # Other Odoo-specific configurations...
}
