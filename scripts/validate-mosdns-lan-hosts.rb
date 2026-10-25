#!/usr/bin/env ruby
# Validate the installed root, not just customization sources.
require_relative '../user/common/files/usr/share/mosdns/sync-adguard-hosts'

module LanHostsImage
  def self.verify(root)
    helper = File.join(root, 'usr/share/mosdns/sync-adguard-hosts.rb')
    source = File.expand_path('../user/common/files/usr/share/mosdns/sync-adguard-hosts.rb', __dir__)
    raise 'Missing/changed installed DNS helper' unless File.executable?(helper) && File.binread(helper) == File.binread(source)
    cfg = PersonalLanHosts.load_yaml(File.join(root, 'etc/mosdns/config_custom.yaml'))
    plugins = cfg.fetch('plugins')
    hosts = plugins.find { |p| p['tag'] == 'hosts' }
    raise 'Missing custom hosts files' unless hosts.dig('args', 'files') == PersonalLanHosts::FILES
    steps = plugins.find { |p| p['tag'] == 'main_sequence' }.fetch('args')
    hi = steps.index { |s| s['exec'] == '$hosts' }
    ci = steps.index { |s| s['exec'] == '$cache' }
    raise 'Installed hosts must run before cache' unless hi && ci && hi < ci
    rows = PersonalLanHosts.records(File.join(root, 'etc/AdGuardHome/AdGuardHome.yaml'))
    generated = File.join(root, 'etc/mosdns/rule/adguard-lan-hosts.txt')
    raise 'Installed DNS mirror differs from AdGuard' unless File.binread(generated) == PersonalLanHosts.render(rows)
    raise 'User hosts file missing' unless File.file?(File.join(root, 'etc/mosdns/rule/hosts.txt'))
    init = File.read(File.join(root, 'etc/init.d/mosdns'))
    raise 'Installed pre-start hook missing' unless init.include?('# lede-personal: prepare exact LAN hosts v1') && init.include?('sync-adguard-hosts.rb sync || return 1') && init.include?('sync-adguard-hosts.rb configure "$CONF" || return 1')
    ruby = File.join(root, 'usr/bin/ruby')
    raise 'Installed Ruby missing' unless File.executable?(ruby)
    entry = File.binread(ruby)
    unless entry.start_with?("\x7fELF")
      # OpenWrt's official Ruby package uses a --disable-gems shell launcher.
      targets = entry.scan(%r{exec (/usr/lib/ruby/ruby[0-9]+\.[0-9]+-bin)\b}).flatten.uniq
      raise 'Unknown Ruby launcher' unless entry.start_with?("#!/bin/sh\n") && targets.size == 1
      binary = File.join(root, targets.first.sub(%r{\A/}, ''))
      raise 'Ruby launcher target missing/invalid' unless File.executable?(binary) && File.binread(binary, 4) == "\x7fELF"
    end
    yaml = Dir.glob(File.join(root, 'usr/lib/ruby/**/yaml.rb'))
    raise 'Installed Ruby YAML missing/invalid' unless yaml.any? { |p| File.read(p).match?(/require\s+['"]psych['"]/) }
    puts "Installed MosDNS LAN mirror verified: #{rows.size} exact records"
  end
end

if $PROGRAM_NAME == __FILE__
  abort 'Usage: validate-mosdns-lan-hosts.rb ROOTFS' unless ARGV.size == 1
  LanHostsImage.verify(File.expand_path(ARGV.first))
end
