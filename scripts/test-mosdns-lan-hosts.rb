#!/usr/bin/env ruby
# Offline tests: real runtime helper, no network or live service mutations.
require 'fileutils'
require 'tmpdir'
require_relative '../user/common/files/usr/share/mosdns/sync-adguard-hosts'

require_relative 'validate-mosdns-lan-hosts'
class LanHostsTest
  ROOT = File.expand_path('..', __dir__)
  def assert(value, message = 'Assertion failed')
    raise message unless value
  end
  def refute(value)
    assert(!value)
  end
  def assert_equal(expected, actual)
    assert(expected == actual, 'Values differ')
  end
  def assert_includes(container, value)
    assert(container.include?(value))
  end
  def refute_includes(container, value)
    refute(container.include?(value))
  end
  def assert_raises(kind)
    begin
      yield
    rescue kind
      return
    end
    raise "Expected #{kind}"
  end
  def setup
    @dir = Dir.mktmpdir('mosdns-lan-hosts-')
    @source = File.join(@dir, 'adguard.yaml')
    @output = File.join(@dir, 'generated.txt')
    @user = File.join(@dir, 'hosts.txt')
    File.write(@user, "# User-owned\nfull:custom.example 192.0.2.9\n")
    write_rows([row])
  end
  def teardown
    FileUtils.remove_entry(@dir)
  end
  def row(domain = 'clash.example.com', ip = '192.0.2.5', enabled = true)
    {'domain' => domain, 'answer' => ip, 'enabled' => enabled}
  end
  def write_rows(rows)
    File.write(@source, YAML.dump({'filtering' => {'rewrites' => rows}}))
  end
  def sync
    PersonalLanHosts.sync(@source, @output, @user)
  end
  def config
    path = File.join(@dir, 'custom.yaml')
    original = File.read(File.join(ROOT, 'app_config/etc/mosdns/config_custom.yaml'))
    parsed = YAML.safe_load(original, aliases: true)
    parsed['plugins'].find { |p| p['tag'] == 'hosts' }['args'].delete('files')
    # Preserve the production layout/anchor, including comments.
    block = PersonalLanHosts::ANCHOR + "      files:\n" + PersonalLanHosts::FILES.map { |f| "        - \"#{f}\"\n" }.join
    text = original.sub(block, PersonalLanHosts::ANCHOR)
    assert_equal parsed, YAML.safe_load(text, aliases: true)
    File.write(path, text)
    path
  end
  def test_exact_deterministic_mapping_and_user_file_preserved
    original = File.read(@user)
    write_rows([row('LEDE.example.com.'), row, row('other.example'), row('off.example.com', '192.0.2.1', false)])
    assert_equal 2, sync
    assert_equal PersonalLanHosts::HEADER + "full:clash.example.com 192.0.2.5\nfull:lede.example.com 192.0.2.5\n", File.read(@output)
    assert_equal original, File.read(@user)
    time = File.stat(@output).mtime
    sync
    assert_equal time, File.stat(@output).mtime
  end
  def test_removed_records_are_not_stale
    sync
    write_rows([])
    assert_equal 0, sync
    assert_equal PersonalLanHosts::HEADER, File.read(@output)
  end
  def test_bad_rewrites_fail_without_modifying_previous_file
    sync
    original = File.read(@output)
    [[row('*.example.com')], [row('example.com')], [row('bad_.example.com')],
     [row('clash.example.com', '999.1.1.1')], [row('clash.example.com', '::1')],
     [row, row], ['not-a-mapping']].each do |bad|
      write_rows(bad)
      assert_raises(ArgumentError) { sync }
      assert_equal original, File.read(@output)
    end
  end
  def test_unmanaged_output_and_symlink_are_not_overwritten
    File.write(@output, 'user data')
    assert_raises(ArgumentError) { sync }
    assert_equal 'user data', File.read(@output)
    File.unlink(@output)
    File.symlink(@user, @output)
    original = File.read(@user)
    assert_raises(ArgumentError) { sync }
    assert_equal original, File.read(@user)
  end
  def test_conflicting_user_entry_is_rejected
    File.write(@user, "full:clash.example.com 192.0.2.6\n")
    assert_raises(ArgumentError) { sync }
    refute File.exist?(@output)
    File.write(@user, "full:clash.example.com 192.0.2.5\n")
    assert_equal 1, sync
  end
  def test_existing_temporary_file_is_preserved
    tmp = "#{@output}.new-#{Process.pid}"
    File.write(tmp, 'unrelated')
    assert_raises(Errno::EEXIST) { sync }
    assert_equal 'unrelated', File.read(tmp)
  end
  def test_config_migration_only_changes_files_and_retains_backup
    path = config
    before = File.read(path)
    expected = YAML.safe_load(before, aliases: true)
    expected['plugins'].find { |p| p['tag'] == 'hosts' }['args']['files'] = PersonalLanHosts::FILES
    assert PersonalLanHosts.configure(path)
    assert_equal expected, YAML.safe_load(File.read(path), aliases: true)
    assert_equal before, File.read(path + '.before-lan-hosts-v1')
    after = File.read(path)
    refute PersonalLanHosts.configure(path)
    assert_equal after, File.read(path)
  end
  def test_custom_files_need_review_without_mutation
    path = config
    text = File.read(path).sub(PersonalLanHosts::ANCHOR, PersonalLanHosts::ANCHOR + "      files: ['/user/custom']\n")
    File.write(path, text)
    assert_raises(ArgumentError) { PersonalLanHosts.configure(path) }
    assert_equal text, File.read(path)
    refute File.exist?(path + '.before-lan-hosts-v1')
  end
  def test_hosts_must_precede_cache
    path = config
    text = File.read(path).sub('exec: $hosts', 'exec: $cache').sub('exec: $cache', 'exec: $hosts')
    # Explicitly remove the only hosts execution; validation must fail closed.
    text = text.gsub('exec: $hosts', 'exec: $cache')
    File.write(path, text)
    assert_raises(ArgumentError) { PersonalLanHosts.configure(path) }
    assert_equal text, File.read(path)
  end
  def test_repository_source_and_build_wiring
    source = File.join(ROOT, 'app_config/etc/AdGuardHome/AdGuardHome.yaml')
    records = PersonalLanHosts.records(source)
    assert_equal 0, records.size
    assert_equal({}, records) # Public source contains no production LAN inventory.
    path = File.join(ROOT, 'app_config/etc/mosdns/config_custom.yaml')
    refute PersonalLanHosts.configure(path) # Checked-in source must already be migrated.
    data = PersonalLanHosts.load_yaml(path)
    plugins = data.fetch('plugins')
    %w[udp_server tcp_server].each do |kind|
      assert plugins.any? { |p| p['type'] == kind && p.dig('args', 'listen') == '127.0.0.1:5335' }
    end
    assert_equal '127.0.0.1:9091', data.dig('api', 'http')
    app = File.read(File.join(ROOT, 'app_config.sh'))
    assert_includes app, 'sync-adguard-hosts.rb" sync'
    assert_includes app, 'scripts/patch-mosdns-lan-hosts.py'
    assert File.executable?(File.join(ROOT, 'user/common/files/usr/share/mosdns/sync-adguard-hosts.rb'))
    keep = File.read(File.join(ROOT, 'user/common/files/lib/upgrade/keep.d/lede-personal-services'))
    assert_includes keep, '/etc/mosdns/rule/hosts.txt'
    refute_includes keep, '/etc/mosdns/rule/adguard-lan-hosts.txt'
  end
  def test_installed_payload_gate_positive_and_missing_or_stale_assets
    root = File.join(@dir, 'rootfs')
    %w[usr/share/mosdns etc/mosdns/rule etc/AdGuardHome etc/init.d usr/bin usr/lib/ruby/3.3].each { |p| FileUtils.mkdir_p(File.join(root, p)) }
    copies = {
      'usr/share/mosdns/sync-adguard-hosts.rb' => 'user/common/files/usr/share/mosdns/sync-adguard-hosts.rb',
      'etc/mosdns/config_custom.yaml' => 'app_config/etc/mosdns/config_custom.yaml',
      'etc/AdGuardHome/AdGuardHome.yaml' => 'app_config/etc/AdGuardHome/AdGuardHome.yaml'
    }
    copies.each { |dst, src| FileUtils.cp(File.join(ROOT, src), File.join(root, dst), preserve: true) }
    File.write(File.join(root, 'etc/mosdns/rule/hosts.txt'), '# user hosts')
    PersonalLanHosts.sync(File.join(root, 'etc/AdGuardHome/AdGuardHome.yaml'), File.join(root, 'etc/mosdns/rule/adguard-lan-hosts.txt'), File.join(root, 'etc/mosdns/rule/hosts.txt'))
    File.binwrite(File.join(root, 'usr/bin/ruby'), "\x7fELF fixture binary")
    File.chmod(0755, File.join(root, 'usr/bin/ruby'))
    File.write(File.join(root, 'usr/lib/ruby/3.3/yaml.rb'), "require 'psych'\n")
    File.write(File.join(root, 'etc/init.d/mosdns'), <<~HOOK)
      # lede-personal: prepare exact LAN hosts v1
      /usr/share/mosdns/sync-adguard-hosts.rb sync || return 1
      /usr/share/mosdns/sync-adguard-hosts.rb configure "$CONF" || return 1
    HOOK
    LanHostsImage.verify(root)
    ruby = File.join(root, 'usr/bin/ruby')
    original_ruby = File.binread(ruby)
    binary = File.join(root, 'usr/lib/ruby/ruby3.3-bin')
    File.binwrite(binary, original_ruby)
    File.chmod(0755, binary)
    File.write(ruby, "#!/bin/sh\nexec /usr/lib/ruby/ruby3.3-bin --disable-gems \"$@\"\n")
    LanHostsImage.verify(root)
    File.unlink(binary)
    assert_raises(RuntimeError) { LanHostsImage.verify(root) }
    File.binwrite(binary, original_ruby)
    File.chmod(0755, binary)
    File.binwrite(ruby, original_ruby)
    %w[usr/share/mosdns/sync-adguard-hosts.rb etc/mosdns/config_custom.yaml etc/mosdns/rule/adguard-lan-hosts.txt etc/init.d/mosdns usr/bin/ruby usr/lib/ruby/3.3/yaml.rb].each do |path|
      full = File.join(root, path)
      old = File.binread(full)
      File.write(full, 'bad payload')
      rejected = false
      begin
        LanHostsImage.verify(root)
      rescue StandardError
        rejected = true
      end
      assert rejected, 'Broken installed payload must fail'
      File.binwrite(full, old)
    end
  end
end

tests = LanHostsTest.instance_methods(false).grep(/^test_/).sort
tests.each do |method|
  test = LanHostsTest.new
  begin
    test.setup
    test.public_send(method)
  ensure
    test.teardown
  end
end
puts "MosDNS LAN hosts: #{tests.size} offline cases passed"
