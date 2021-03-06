#
# Unit tests for neutron::plugins::ml2 class
#

require 'spec_helper'

describe 'neutron::plugins::ml2::cisco::nexus' do

  let :pre_condition do
    "class { 'neutron::server': auth_password => 'password'}
     class { 'neutron':
      rabbit_password => 'passw0rd',
      core_plugin     => 'neutron.plugins.ml2.plugin.Ml2Plugin' }"
  end

  let :default_params do
    {
      :nexus_config          => nil
    }
  end

  let :params do
    {}
  end

  let :facts do
    { :operatingsystem         => 'default',
      :operatingsystemrelease  => 'default',
      :osfamily                => 'Debian'
    }
  end

  context 'fail when missing nexus_config' do
    it_raises 'a Puppet::Error', /No nexus config specified/
  end

  context 'when using cisco' do
    let (:nexus_config) do
      { 'cvf2leaff2' => {'username' => 'prad',
        "ssh_port" => 22,
        "password" => "password",
        "ip_address" => "172.18.117.28",
        "servers" => {
          "control02" => "portchannel:20",
          "control01" => "portchannel:10"
        }
      }
    }
    end

    before :each do
      params.merge!(:nexus_config => nexus_config )
    end

    it 'installs ncclient package' do
      is_expected.to contain_package('python-ncclient').with(
        :ensure => 'installed',
        :tag    => 'openstack'
      )
    end

  end

end
