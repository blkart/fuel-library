require File.join File.dirname(__FILE__), '../test_common.rb'

class SslKeysSavingPreTest < Test::Unit::TestCase

  def test_ssl_data
    assert TestCommon::Settings.lookup('public_ssl'), 'No SSL hash found in Hiera!'
  end

end
