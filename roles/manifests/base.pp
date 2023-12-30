class profile::base {
  # Ensure system is up-to-date
  exec { 'update-package-list':
    command => 'apt update',
    path    => ['/bin', '/usr/bin'],
    timeout => 180,
  }

  # Install common packages
  package { ['openssh-server', 'fail2ban', 'jq']:
    ensure  => installed,
    require => Exec['update-package-list'],
  }
  
    # Install PostgreSQL
  package { 'postgresql':
    ensure => installed,
  }
  
  # Other common system configurations...


}
