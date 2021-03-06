#
# Authors: Emilien Macchi <emilien.macchi@enovance.com>
#          Francois Charlier <francois.charlier@enovance.com>
#

require 'spec_helper'
require 'tempfile'

describe Puppet::Type.type(:mongodb_replset).provider(:mongo) do

  valid_members = ['mongo1:27017', 'mongo2:27017', 'mongo3:27017']

  let(:resource) { Puppet::Type.type(:mongodb_replset).new(
    { :ensure        => :present,
      :name          => 'rs_test',
      :members       => valid_members,
      :provider      => :mongo
    }
  )}

  let(:resources) { { 'rs_test' => resource } }
  let(:provider) { described_class.new(resource) }

  describe '#create' do
    before :each do
      tmp = Tempfile.new('test')
      @mongodconffile = tmp.path
      provider.class.stubs(:get_mongod_conf_file).returns(@mongodconffile)
      File.stubs(:exists?).with('/root/.mongorc.js').returns(true)
      File.stubs(:exist?).with('/root/.mongorc.js').returns(true)
    end

    xit 'should create a replicaset' do
      provider.class.stubs(:get_replset_properties)
      provider.stubs(:alive_members).returns(valid_members)
      provider.expects('rs_initiate').with("{ _id: \"rs_test\", members: [ { _id: 0, host: \"mongo1:27017\" },{ _id: 1, host: \"mongo2:27017\" },{ _id: 2, host: \"mongo3:27017\" } ] }", "mongo1:27017").returns(
        { "info" => "Config now saved locally.  Should come online in about a minute.",
          "ok"   => 1 } )
      provider.create
      provider.flush
    end

    it 'raises an error when no member is available' do
      provider.stubs('primary?').returns(false)
      provider.class.stubs(:alive_members).returns([])
      provider.class.stubs(:mongo).returns('{}')
      provider.create
      expect { provider.flush }.to raise_error(Puppet::Error, "Can't connect to any member of replicaset #{resource[:name]}.")
    end
  end

  describe '#exists?' do
    before :each do
      tmp = Tempfile.new('test')
      @mongodconffile = tmp.path
      provider.class.stubs(:get_mongod_conf_file).returns(@mongodconffile)
      File.stubs(:exists?).with('/root/.mongorc.js').returns(true)
      File.stubs(:exist?).with('/root/.mongorc.js').returns(true)
    end
    describe 'when the replicaset does not exist' do
      it 'returns false' do
        provider.class.stubs(:mongo).returns(<<EOT)
{
	"startupStatus" : 3,
	"info" : "run rs.initiate(...) if not yet done for the set",
	"ok" : 0,
	"errmsg" : "can't get local.system.replset config from self or any seed (EMPTYCONFIG)"
}
EOT
        provider.class.prefetch(resources)
        resource.provider.exists?.should eql false
      end
    end

    describe 'when the replicaset exists' do
      it 'returns true' do
        provider.class.stubs(:mongo).returns(<<EOT)
{
	"_id" : "rs_test",
	"version" : 1,
	"members" : [ ]
}
EOT
        provider.class.prefetch(resources)
        resource.provider.exists?.should eql true
      end
    end
  end

  describe '#members' do
    before :each do
      tmp = Tempfile.new('test')
      @mongodconffile = tmp.path
      provider.class.stubs(:get_mongod_conf_file).returns(@mongodconffile)
      File.stubs(:exists?).with('/root/.mongorc.js').returns(true)
      File.stubs(:exist?).with('/root/.mongorc.js').returns(true)
    end
    it 'returns the members of a configured replicaset' do
      provider.class.stubs(:mongo).returns(<<EOT)
{
	"_id" : "rs_test",
	"version" : 1,
	"members" : [
		{
			"_id" : 0,
			"host" : "mongo1:27017"
		},
		{
			"_id" : 1,
			"host" : "mongo2:27017"
		},
		{
			"_id" : 2,
			"host" : "mongo3:27017"
		}
	]
}
EOT
      provider.class.prefetch(resources)
      resource.provider.members.should =~ valid_members
    end
  end

  describe 'members=' do
    before :each do
      tmp = Tempfile.new('test')
      @mongodconffile = tmp.path
      provider.class.stubs(:get_mongod_conf_file).returns(@mongodconffile)
      File.stubs(:exists?).with('/root/.mongorc.js').returns(true)
      File.stubs(:exist?).with('/root/.mongorc.js').returns(true)
    end
    before :each do
      provider.class.stubs(:mongo).returns(<<EOT)
{
	"setName" : "rs_test",
	"ismaster" : true,
	"secondary" : false,
	"hosts" : [
		"mongo1:27017"
	],
	"primary" : "mongo1:27017",
	"me" : "mongo1:27017",
	"maxBsonObjectSize" : 16777216,
	"maxMessageSizeBytes" : 48000000,
	"localTime" : ISODate("2014-01-10T19:31:51.281Z"),
	"ok" : 1
}
EOT
    end

    it 'adds missing members to an existing replicaset' do
      provider.class.stubs(:mongo_eval).with('db.isMaster().ismaster').returns('true')
      tmp = Tempfile.new('test')
      @mongodconffile = tmp.path
      provider.class.stubs(:get_mongod_conf_file).returns(@mongodconffile)
      provider.stubs(:rs_status).returns({ "set" => "rs_test" })
      provider.expects('primary?').times(1)
      provider.members=(valid_members)
      provider.flush
    end

   it 'raises an error when the master host is not available' do
      provider.stubs('primary?').returns(true)
      provider.create
      expect { provider.flush }.to raise_error(Puppet::Error, "Can't connect to any member of replicaset #{resource[:name]}.")
    end


   it 'raises an error when the master host is not available' do
      provider.stubs('primary?').returns(true)
      provider.stubs('master_host').returns(false)
      provider.members=(valid_members)
      expect { provider.flush }.to raise_error(Puppet::Error, "Can't connect to any member of replicaset #{resource[:name]}.")
    end

    it 'raises an error when at least one member is not running with --replSet' do
      provider.stubs('primary?').returns(true)
      provider.stubs(:rs_status).returns({ "ok" => 0, "errmsg" => "not running with --replSet" })
      provider.members=(valid_members)
      expect { provider.flush }.to raise_error(Puppet::Error, /is not supposed to be part of a replicaset\.$/)
    end

    it 'raises an error when at least one member is configured with another replicaset name' do
      provider.stubs('primary?').returns(true)
      provider.stubs(:rs_status).returns({ "set" => "rs_another" })
      provider.members=(valid_members)
      expect { provider.flush }.to raise_error(Puppet::Error, /is already part of another replicaset\.$/)
    end

  end #members=
end
