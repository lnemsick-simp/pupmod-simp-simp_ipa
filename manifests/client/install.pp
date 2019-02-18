# @summary Run ipa-client-install on puppet clients
#
# @note Not all parameters here are required. If the DNS is properly configured
#   on the host, nothing needs to be set besides $password. Be sure to read the
#   man page in ipa-client-install or the help for guidance
#
# @note This class supports adding a host to a domain and removing it, but not
#   changing it
#
# @see ipa-client-install(1)
#
# @param ensure
#   'present' to add host to an IPA domain, 'absent' to remove
#
# @param ip_address
#   IP address of host being connected
#
# @param hostname
#   Hostname of the host being connected
#
# @param password
#   The password used for joining. The password can be of one of two types:
#     * If $principal is set, this is the password relating to
#       that administrative user
#     * A one time password. A host-based one-time-password generated by
#       ``ipa host-add`` or the GUI
#
# @param principal
#   The administrative user krb5 principal that $password relates to, if the $password is not
#   a one time password
#
# @param server
#   IPA server to connect to
#
# @param domain
#   IPA Domain
#
# @param realm
#   IPA Realm
#
# @param no_ac
#   Run without authconfig, defaults to true, appropriate on systems
#   using ``simp/pam``
#
# @param install_options
#   Hash of other options for the ``ipa-client-install`` command.  Any key
#   here that is also a class parameters will be overwritten with the value
#   of the corresponding class parameter. Also, if the option doesn't need a
#   value, (e.g., the `debug` option), just set the value of the setting to
#   Undef or nil in Hiera.
#
#   @see ``ipa-client-install --help``
#
# @param ipa_client_ensure
#   Ensure attribute of the package resource managing the ``ipa-client`` package
#
# @param admin_tools_ensure
#   Ensure attribute of the package resource managing the ``ipa-admintools``
#   package. Only applicable on EL6.
#
class simp_ipa::client::install (
  Enum['present','absent']           $ensure,
  Optional[Simplib::Hostname]        $hostname   = undef,
  Optional[String]                   $password   = undef,
  Optional[String]                   $principal  = undef,
  Optional[Simplib::Hostname]        $domain     = undef,
  Optional[String]                   $realm      = undef,
  Optional[Array[Simplib::Hostname]] $server     = undef,
  Optional[Array[Simplib::Host]]     $ntp_server = undef,
  Optional[Array[Simplib::IP]]       $ip_address = undef,
  Boolean                            $no_ac      = true,
  Hash                               $install_options = {},
  String $ipa_client_ensure  = simplib::lookup('simp_options::package_ensure', { 'default_value' => 'installed' }),
  String $admin_tools_ensure = simplib::lookup('simp_options::package_ensure', { 'default_value' => 'installed' }),
) {
  contain 'simp_ipa::client::packages'

  if $domain and $ensure == 'present' {
    if $facts['ipa'] {
      if $facts['ipa']['domain'] != $domain {
        fail("simp_ipa::client::install: This host is already a member of domain ${facts['ipa']['domain']}, cannot join domain ${domain}")
      }
    }
  }


  # assemble important options into hash, then remove ones that are undef
  # all of these options require a value
  $opts = {
    'password'   => $password,
    'principal'  => $principal,
    'server'     => $server,
    'ip-address' => $ip_address,
    'domain'     => $domain,
    'realm'      => $realm,
    'hostname'   => $hostname,
    'ntp-server' => $ntp_server,
  }.delete_undef_values

  $_no_ac = $no_ac ? { true => { 'noac'  => undef }, default => {} }

  # convert the hash into a string
  $expanded_options = simplib::hash_to_opts(
    ($install_options + $_no_ac + $opts),
    { 'repeat' => 'repeat' }
  )


  if $ensure == 'present' {
    unless $facts['ipa'] {
      exec { 'ipa-client-install install':
        command   => strip("ipa-client-install --unattended ${expanded_options}"),
        logoutput => true,
        path      => ['/sbin','/usr/sbin'],
        require   => Class['simp_ipa::client::packages']
      }
    }
  }
  else {
    exec { 'ipa-client-install uninstall':
      command   => 'ipa-client-install --unattended --uninstall',
      logoutput => true,
      path      => ['/sbin','/usr/sbin'],
      require   => Class['simp_ipa::client::packages'],
      notify    => Reboot_notify['ipa-client-unstall uninstall']
    }
    # you might not have to do this
    reboot_notify { 'ipa-client-unstall uninstall':
      reason => 'simp_ipa::client::install: removed host from IPA domain'
    }
  }
}
