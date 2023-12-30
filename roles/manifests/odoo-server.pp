class role::odoo_server {
  include profile::base
  include profile::user_management
  include profile::odoo
  include profile::database

  # Any other specific configurations for an Odoo server...
}
