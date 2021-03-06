## NB: This must work with Ruby 1.8!

# This providers permits the nova_admin_tenant_id paramter in neutron.conf
# to be set by providing a nova_admin_tenant_name to the Puppet module and
# using the Keystone REST API to translate the name into the corresponding
# UUID.
#
# This requires that tenant names be unique.  If there are multiple matches
# for a given tenant name, this provider will raise an exception.

require 'rubygems'
require 'net/http'
require 'net/https'
require 'json'
require 'puppet/util/inifile'

class KeystoneError < Puppet::Error
end

class KeystoneConnectionError < KeystoneError
end

class KeystoneAPIError < KeystoneError
end

Puppet::Type.type(:nova_admin_tenant_id_setter).provide(:ruby) do
  @tenant_id = nil

  def authenticate
    keystone_v2_authenticate(
        @resource[:auth_url],
        @resource[:auth_username],
        @resource[:auth_password],
        nil,
        @resource[:auth_tenant_name])
  end

  def find_tenant_by_name (token)
    tenants = keystone_v2_tenants(
        @resource[:auth_url],
        token)

    tenants.select { |tenant| tenant['name'] == @resource[:tenant_name] }
  end

  # Provides common request handling semantics to the other methods in
  # this module.
  #
  # +req+::
  #   An HTTPRequest object
  # +url+::
  #   A parsed URL (returned from URI.parse)
  def neutron_handle_request(req, url)
    begin
      # There is issue with ipv6 where address has to be in brackets, this causes the
      # underlying ruby TCPSocket to fail. Net::HTTP.new will fail without brackets on
      # joining the ipv6 address with :port or passing brackets to TCPSocket. It was
      # found that if we use Net::HTTP.start with url.hostname the incriminated code
      # won't be hit.
      use_ssl = url.scheme == "https" ? true : false
      http = Net::HTTP.start(url.hostname, url.port, {:use_ssl => use_ssl})
      res = http.request(req)

      if res.code != '200'
        raise KeystoneAPIError, "Received error response from Keystone server at #{url}: #{res.message}"
      end
    rescue Errno::ECONNREFUSED => detail
      raise KeystoneConnectionError, "Failed to connect to Keystone server at #{url}: #{detail}"
    rescue SocketError => detail
      raise KeystoneConnectionError, "Failed to connect to Keystone server at #{url}: #{detail}"
    end

    res
  end

  # Authenticates to a Keystone server and obtains an authentication token.
  # It returns a 2-element +[token, authinfo]+, where +token+ is a token
  # suitable for passing to openstack apis in the +X-Auth-Token+ header, and
  # +authinfo+ is the complete response from Keystone, including the service
  # catalog (if available).
  #
  # +auth_url+::
  #   Keystone endpoint URL.  This function assumes API version
  #   2.0 and an administrative endpoint, so this will typically look like
  #   +http://somehost:35357/v2.0+.
  #
  # +username+::
  #   Username for authentication.
  #
  # +password+::
  #   Password for authentication
  #
  # +tenantID+::
  #   Tenant UUID
  #
  # +tenantName+::
  #   Tenant name
  #

  def keystone_v2_authenticate(auth_url,
                                       username,
                                       password,
                                       tenantId=nil,
                                       tenantName=nil)
    debug 'Call: keystone_v2_authenticate'

    post_args = {
        'auth' => {
            'passwordCredentials' => {
                'username' => username,
                'password' => password
            },
        }}

    if tenantId
      post_args['auth']['tenantId'] = tenantId
    end

    if tenantName
      post_args['auth']['tenantName'] = tenantName
    end

    url = URI.parse("#{auth_url}/tokens")
    req = Net::HTTP::Post.new url.path
    req['content-type'] = 'application/json'
    req.body = post_args.to_json

    res = neutron_handle_request(req, url)
    data = JSON.parse res.body
    return data['access']['token']['id']
  end

  # Queries a Keystone server to a list of all tenants.
  #
  # +auth_url+::
  #   Keystone endpoint.  See the notes for +auth_url+ in
  #   +keystone_v2_authenticate+.
  #
  # +token+::
  #   A Keystone token that will be passed in requests as the value of the
  #   +X-Auth-Token+ header.
  #

  def keystone_v2_tenants(auth_url, token)
    debug 'Call: keystone_v2_tenants'
    url = URI.parse("#{auth_url}/tenants")
    req = Net::HTTP::Get.new url.path
    req['content-type'] = 'application/json'
    req['x-auth-token'] = token

    res = neutron_handle_request(req, url)
    data = JSON.parse res.body
    data['tenants']
  end

  # This looks for the tenant specified by the 'tenant_name' parameter to
  # the resource and returns the corresponding UUID if there is a single
  # match.
  #
  # Raises a KeystoneAPIError if:
  #
  # - There are multiple matches, or
  # - There are zero matches
  def get_tenant_id
    debug 'Call: get_tenant_id'
    exception = nil
    retry_count.times do
      begin
        return get_tenant_id_request
      rescue => exception
        debug exception.message
        break if exception.message.include? 'multiple matches'
        sleep retry_sleep
        next
      end
    end
    raise exception if exception
  end

  def get_tenant_id_request
    debug 'Call: get_tenant_id_request'
    token = authenticate
    tenants = find_tenant_by_name(token)

    if tenants.length == 1
      return tenants.first['id']
    elsif tenants.length > 1
      raise KeystoneAPIError, "Found multiple matches for domain name: '#{tenants.first['name']}' while geting the id of the tenant: '#{@resource[:tenant_name]}'!"
    else
      raise KeystoneAPIError, "Unable to find matching tenant: '#{@resource[:tenant_name]}'!"
    end
  end

  ###################################

  def retry_count
    10
  end

  def retry_sleep
    3
  end

  def exists?
    debug 'Call: exists?'
    ini_file = Puppet::Util::IniConfig::File.new
    ini_file.read("/etc/neutron/neutron.conf")
    ini_file['DEFAULT'] && ini_file['DEFAULT']['nova_admin_tenant_id'] && ini_file['DEFAULT']['nova_admin_tenant_id'] == tenant_id
  end

  def create
    config
  end

  def tenant_id
    @tenant_id ||= get_tenant_id
  end

  def config
    Puppet::Type.type(:neutron_config).new(
        {:name => 'DEFAULT/nova_admin_tenant_id', :value => "#{tenant_id}"}
    ).create
  end

end

