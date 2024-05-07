require 'test_helper'
require 'net/http'

class ClientVerificationIntegrationTest < Test::Unit::TestCase
  def setup
    WebMock.disable_net_connect!(allow_localhost: true)
    @server = WEBrick::HTTPServer.new(Port: 0,
                                      Logger: WEBrick::Log.new("/dev/null"))
    @server.mount_proc '/' do |req, res|
      res.body = 'Success'
    end
    @thread = Thread.new { @server.start }
  end

  def teardown
    @thread.exit
    @thread.join
  end

  def test_http
    res = Net::HTTP.get_response('localhost', '/', @server.config[:Port])
    assert_kind_of Net::HTTPSuccess, res
    assert_equal 'Success', res.body
  end
end

class SSLClientVerificationIntegrationTest < Test::Unit::TestCase
  def setup
    WebMock.disable_net_connect!(allow_localhost: true)
    @ssl_private_key = OpenSSL::PKey::RSA.new(File.read(File.join(fixtures, 'private_keys', 'server.example.com.pem')))
    @ssl_certificate = OpenSSL::X509::Certificate.new(File.read(File.join(fixtures, 'certs', 'server.example.com.pem')))
    @ssl_ca_file = File.join(fixtures, 'certs', 'ca.pem')
    @server = WEBrick::HTTPServer.new(Port: 0,
                                      SSLEnable: true,
                                      SSLCertificate: @ssl_certificate,
                                      SSLPrivateKey: @ssl_private_key,
                                      SSLCACertificateFile: @ssl_ca_file,
                                      SSLVerifyClient: OpenSSL::SSL::VERIFY_PEER,
                                      Logger: WEBrick::Log.new("/dev/null"))
    @server.mount_proc '/' do |req, res|
      res.body = 'Success'
    end
    @thread = Thread.new { @server.start }
  end

  def teardown
    @thread.exit
    @thread.join
  end

  def test_https_no_cert
    http = Net::HTTP.new('localhost', @server.config[:Port])
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    assert_raise OpenSSL::SSL::SSLError do
      http.get('/')
    end
  end

  def test_https_cert_from_different_authority
    http = Net::HTTP.new('localhost', @server.config[:Port])
    http.use_ssl = true
    http.ca_file = File.join(fixtures, 'certs', 'ca.pem')
    http.cert    = OpenSSL::X509::Certificate.new(File.read(File.join(fixtures, 'certs', 'badclient.example.com.pem')))
    http.key     = OpenSSL::PKey::RSA.new(File.read(File.join(fixtures, 'private_keys', 'badclient.example.com.pem')))
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    assert_raise OpenSSL::SSL::SSLError do
      http.get('/')
    end
  end

  def test_https_cert
    http = Net::HTTP.new('localhost', @server.config[:Port])
    http.use_ssl = true
    http.ca_file = @ssl_ca_file
    http.cert = @ssl_certificate
    http.key = @ssl_private_key
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    res = http.get('/')
    assert_kind_of Net::HTTPSuccess, res
    assert_equal 'Success', res.body
  end

  private

  def fixtures
    File.expand_path(File.join(__dir__, '..', 'fixtures', 'ssl'))
  end
end
