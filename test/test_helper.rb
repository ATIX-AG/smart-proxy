require 'English'
require "test/unit"
require 'fileutils'

$LOAD_PATH << File.join(__dir__, '..', 'lib')
$LOAD_PATH << File.join(__dir__, '..', 'modules')

logdir = File.join(__dir__, '..', 'logs')
FileUtils.mkdir_p(logdir) unless File.exist?(logdir)

ENV['RACK_ENV'] = 'test'

# Make sure that tests put their temp files in a controlled location
# Clear temp file before each test run
ENV['TMPDIR'] = 'test/tmp'
FileUtils.rm_f Dir.glob 'test/tmp/*.tmp'

require "mocha/test_unit"
require "rack/test"
require 'timeout'
require 'webmock/test_unit'

require 'smart_proxy_for_testing'
require 'provider_interface_validation/dhcp_provider'

include DhcpProviderInterfaceValidation

def hash_symbols_to_strings(hash)
  Hash[hash.collect { |k, v| [k.to_s, v] }]
end

class SmartProxyRootApiTestCase < Test::Unit::TestCase
  include Rack::Test::Methods

  def setup
    Proxy::LogBuffer::Buffer.instance.send(:reset)
  end

  def app
    Proxy::PluginInitializer.new(Proxy::Plugins.instance).initialize_plugins
    Proxy::RootV2Api.new
  end
end
