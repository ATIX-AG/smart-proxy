require 'test_helper'
require 'tftp/server'
require 'tftp/tftp_plugin'
require 'tempfile'

module TftpGenericServerSuite
  def setup
    @rootdir = "/some/root"
    @mac = "aa:bb:cc:dd:ee:ff"
    @content = "file content"
    Proxy::TFTP::Plugin.settings.stubs(:tftproot).returns(@rootdir)
    setup_paths
  end

  def pxe_config_files
    @pxe_config_files.collect { |f| File.join(@rootdir, f) }
  end

  def pxe_default_files
    @pxe_default_files.collect { |f| File.join(@rootdir, f) }
  end

  def test_set
    pxe_config_files.each do |file|
      @subject.expects(:write_file).with(file, @content).once
    end
    @subject.set @mac, @content
  end

  def test_del
    pxe_config_files.each do |file|
      @subject.expects(:delete_file).with(file).once
    end
    @subject.del @mac
  end

  def test_get
    file = pxe_config_files.first
    @subject.expects(:read_file).with(file).returns(@content)
    assert_equal @content, @subject.get(@mac)
  end

  def test_create_default
    pxe_default_files.each do |file|
      @subject.expects(:write_file).with(file, @content).once
    end
    @subject.create_default @content
  end
end

class HelperServerTest < Test::Unit::TestCase
  def setup
    @subject = Proxy::TFTP::Server.new
  end

  def test_path_with_settings
    Proxy::TFTP::Plugin.settings.expects(:tftproot).returns("/some/root")
    assert_equal "/some/root", @subject.path
  end

  def test_path
    assert_match /file.txt/, @subject.path("file.txt")
  end

  def test_read_file
    file = Tempfile.new('foreman-proxy-tftp-server-read-file.txt')
    file.write("test")
    file.close
    assert_equal ["test"], @subject.read_file(file.path)
  ensure
    file.unlink
  end

  def test_write_file
    tmp_filename = File.join(Dir.tmpdir(), 'foreman-proxy-tftp-server-write-file.txt')
    @subject.write_file(tmp_filename, "test")
    assert_equal "test", File.open(tmp_filename, "rb").read
  ensure
    File.unlink(tmp_filename) if tmp_filename
  end

  def test_delete_file
    tmp_filename = File.join(Dir.tmpdir(), 'foreman-proxy-tftp-server-write-file.txt')
    @subject.delete_file tmp_filename
    assert_equal false, File.exist?(tmp_filename)
  ensure
    File.unlink(tmp_filename) if File.exist?(tmp_filename)
  end
end

class TftpSyslinuxServerTest < Test::Unit::TestCase
  include TftpGenericServerSuite

  def setup_paths
    @subject = Proxy::TFTP::Syslinux.new
    @pxe_config_files = ["pxelinux.cfg/01-aa-bb-cc-dd-ee-ff"]
    @pxe_default_files = ["pxelinux.cfg/default"]
  end
end

class TftpPxegrubServerTest < Test::Unit::TestCase
  include TftpGenericServerSuite

  def setup_paths
    @subject = Proxy::TFTP::Pxegrub.new
    @pxe_config_files = ["grub/menu.lst.01AABBCCDDEEFF", "grub/01-AA-BB-CC-DD-EE-FF"]
    @pxe_default_files = ["grub/menu.lst", "grub/efidefault"]
  end
end

class TftpPxegrub2ServerTest < Test::Unit::TestCase
  include TftpGenericServerSuite

  def setup
    @arch = "x86_64"
    @bootfile_suffix = "x64"
    @os = "redhat"
    @release = "9.4"
    super
  end

  def setup_paths
    @subject = Proxy::TFTP::Pxegrub2.new
    @pxe_config_files = [
      "host-config/aa-bb-cc-dd-ee-ff/grub2/grub.cfg",
      "host-config/aa-bb-cc-dd-ee-ff/grub2/grub.cfg-01-aa-bb-cc-dd-ee-ff",
      "host-config/aa-bb-cc-dd-ee-ff/grub2/grub.cfg-aa:bb:cc:dd:ee:ff",
      "grub2/grub.cfg-01-aa-bb-cc-dd-ee-ff",
      "grub2/grub.cfg-aa:bb:cc:dd:ee:ff",
    ]
    @pxe_default_files = ["grub2/grub.cfg"]
  end

  def setup_bootloader_common(version)
    pxeconfig_dir_mac = @subject.pxeconfig_dir(@mac)
    FileUtils.stubs(:mkdir_p).with(pxeconfig_dir_mac).returns(true).once
    Dir.stubs(:glob).with(File.join(pxeconfig_dir_mac, "*.efi")).returns([]).once
    universe_base_path = "bootloader-universe/pxegrub2"
    Dir.stubs(:exist?).with(File.join(@subject.path, universe_base_path, @os, @release, @arch)).returns(false).once if version != @release
    bootloader_path = File.join(@subject.path, universe_base_path, @os, version, @arch)
    Dir.stubs(:exist?).with(bootloader_path).returns(true).once
    Dir.stubs(:glob).with(File.join(bootloader_path, "*.efi")).returns([
                                                                         File.join(bootloader_path, "boot.efi"),
                                                                         File.join(bootloader_path, "boot-sb.efi"),
                                                                         File.join(bootloader_path, "grubx64.efi"),
                                                                         File.join(bootloader_path, "shimx64.efi"),
                                                                       ]).once
    relative_bootloader_path = File.join("../../..", universe_base_path, @os, version, @arch)
    FileUtils.stubs(:ln_s).with(File.join(relative_bootloader_path, "boot.efi"), File.join(pxeconfig_dir_mac, "boot.efi"), {:force => true}).returns(true).once
    FileUtils.stubs(:ln_s).with(File.join(relative_bootloader_path, "boot-sb.efi"), File.join(pxeconfig_dir_mac, "boot-sb.efi"), {:force => true}).returns(true).once
    FileUtils.stubs(:ln_s).with(File.join(relative_bootloader_path, "grubx64.efi"), File.join(pxeconfig_dir_mac, "grubx64.efi"), {:force => true}).returns(true).once
    FileUtils.stubs(:ln_s).with(File.join(relative_bootloader_path, "shimx64.efi"), File.join(pxeconfig_dir_mac, "shimx64.efi"), {:force => true}).returns(true).once

    @subject.setup_bootloader(mac: @mac, os: @os, release: @release, arch: @arch, bootfile_suffix: @bootfile_suffix)
  end

  def test_setup_bootloader
    pxeconfig_dir_mac = @subject.pxeconfig_dir(@mac)
    FileUtils.stubs(:mkdir_p).with(pxeconfig_dir_mac).returns(true).once
    relative_bootloader_path = "../../../grub2/"
    FileUtils.stubs(:ln_s).with(File.join(relative_bootloader_path, "grubx64.efi"), File.join(pxeconfig_dir_mac, "boot.efi"), {:force => true}).returns(true).once
    FileUtils.stubs(:ln_s).with(File.join(relative_bootloader_path, "grubx64.efi"), File.join(pxeconfig_dir_mac, "grubx64.efi"), {:force => true}).returns(true).once
    FileUtils.stubs(:ln_s).with(File.join(relative_bootloader_path, "shimx64.efi"), File.join(pxeconfig_dir_mac, "boot-sb.efi"), {:force => true}).returns(true).once
    FileUtils.stubs(:ln_s).with(File.join(relative_bootloader_path, "shimx64.efi"), File.join(pxeconfig_dir_mac, "shimx64.efi"), {:force => true}).returns(true).once

    @subject.setup_bootloader(mac: @mac, os: @os, release: @release, arch: @arch, bootfile_suffix: @bootfile_suffix)
  end

  def test_setup_bootloader_from_unversioned_bootloader_universe
    setup_bootloader_common("default")
  end

  def test_setup_bootloader_from_versioned_bootloader_universe
    setup_bootloader_common(@release)
  end
end

class TftpPoapServerTest < Test::Unit::TestCase
  include TftpGenericServerSuite

  def setup_paths
    @subject = Proxy::TFTP::Poap.new
    @pxe_config_files = ["poap.cfg/AABBCCDDEEFF"]
  end

  def test_create_default
    # default template not supported in this case
  end
end

class TftpZtpServerTest < Test::Unit::TestCase
  include TftpGenericServerSuite

  def setup_paths
    @subject = Proxy::TFTP::Ztp.new
    @pxe_config_files = ["ztp.cfg/AABBCCDDEEFF", "ztp.cfg/AABBCCDDEEFF.cfg"]
  end

  def test_create_default
    # default template not supported in this case
  end
end

class TftpIpxeServerTest < Test::Unit::TestCase
  include TftpGenericServerSuite

  def setup_paths
    @subject = Proxy::TFTP::Ipxe.new
    @pxe_config_files = ["pxelinux.cfg/01-aa-bb-cc-dd-ee-ff.ipxe"]
    @pxe_default_files = ["pxelinux.cfg/default.ipxe"]
  end
end
