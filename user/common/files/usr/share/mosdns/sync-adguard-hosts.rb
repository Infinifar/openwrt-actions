#!/usr/bin/ruby
# Derived, exact local DNS records. AdGuardHome remains the source of truth.
require 'yaml'
# OpenWrt init and CI may run in the C locale; configuration is UTF-8.
Encoding.default_external = Encoding::UTF_8

module PersonalLanHosts
  HEADER = "# Generated from enabled AdGuardHome example.com IPv4 rewrites; do not edit.\n"
  FILES = ['/etc/mosdns/rule/hosts.txt', '/etc/mosdns/rule/adguard-lan-hosts.txt'].freeze
  ANCHOR = "  - tag: hosts\n    type: hosts\n    args:\n"

  def self.load_yaml(path)
    data = YAML.safe_load(File.read(path), permitted_classes: [Symbol], aliases: true)
    raise ArgumentError, 'Expected a YAML mapping' unless data.is_a?(Hash)
    data
  end

  def self.records(source)
    rows = load_yaml(source).dig('filtering', 'rewrites')
    raise ArgumentError, 'AdGuard filtering.rewrites must be an array' unless rows.is_a?(Array)
    out = {}
    rows.each do |row|
      raise ArgumentError, 'Invalid rewrite object' unless row.is_a?(Hash)
      next if row['enabled'] == false
      domain = row['domain'].to_s.downcase.sub(/\.$/, '')
      next unless domain == 'example.com' || domain.end_with?('.example.com')
      labels = domain.split('.')
      unless domain != 'example.com' && labels.all? { |s| s.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/) }
        raise ArgumentError, 'Only exact example.com subdomains may be mirrored'
      end
      address = row['answer'].to_s
      parts = address.split('.')
      unless parts.size == 4 && parts.all? { |p| p.match?(/\A(?:0|[1-9][0-9]{0,2})\z/) && p.to_i <= 255 }
        raise ArgumentError, 'Local mirror only supports explicit IPv4 answers'
      end
      raise ArgumentError, 'Duplicate local rewrite; resolve it in AdGuard first' if out.key?(domain)
      out[domain] = address
    end
    out.sort.to_h
  end

  def self.render(rows)
    HEADER + rows.map { |domain, ip| "full:#{domain} #{ip}\n" }.join
  end

  def self.atomic_write(path, content, mode)
    raise ArgumentError, 'Refusing a symlink destination or parent' if File.symlink?(path) || File.symlink?(File.dirname(path))
    return false if File.file?(path) && File.binread(path) == content
    tmp = "#{path}.new-#{Process.pid}"
    created = false
    begin
      File.open(tmp, File::WRONLY | File::CREAT | File::EXCL, mode) do |file|
        created = true
        file.write(content)
        file.flush
        file.fsync
      end
      File.rename(tmp, path)
    ensure
      File.unlink(tmp) if created && File.exist?(tmp) && !File.symlink?(tmp)
    end
    true
  end

  def self.sync(source, output, user_hosts)
    rows = records(source)
    if File.file?(user_hosts)
      File.foreach(user_hosts) do |line|
        fields = line.split('#', 2).first.to_s.split
        next if fields.empty?
        name = fields.first.sub(/\Afull:/, '').downcase.sub(/\.$/, '')
        if rows.key?(name) && fields.drop(1) != [rows[name]]
          raise ArgumentError, 'User hosts conflicts with AdGuard; original files retained'
        end
      end
    end
    if File.exist?(output) && !File.binread(output).start_with?(HEADER)
      raise ArgumentError, 'Refusing to replace an unmanaged hosts file'
    end
    atomic_write(output, render(rows), 0644)
    rows.size
  end

  # Preserve the custom YAML byte-for-byte except for the owned files field.
  # This also handles a previous custom config restored by sysupgrade.
  def self.configure(path)
    cfg = load_yaml(path)
    plugins = cfg['plugins']
    raise ArgumentError, 'Missing plugin array' unless plugins.is_a?(Array)
    hosts = plugins.select { |p| p['tag'] == 'hosts' }
    raise ArgumentError, 'Expected exactly one hosts plugin' unless hosts.size == 1 && hosts.first['type'] == 'hosts'
    args = hosts.first['args']
    raise ArgumentError, 'Invalid hosts arguments' unless args.is_a?(Hash)
    steps = plugins.find { |p| p['tag'] == 'main_sequence' }.to_h['args'] || []
    host_index = steps.index { |s| s['exec'] == '$hosts' }
    cache_index = steps.index { |s| s['exec'] == '$cache' }
    raise ArgumentError, 'Hosts must execute before cache' unless host_index && cache_index && host_index < cache_index
    return false if args['files'].is_a?(Array) && (FILES - args['files']).empty?
    raise ArgumentError, 'Custom hosts files need manual review; config retained' if args.key?('files')
    before = File.binread(path)
    raise ArgumentError, 'Unrecognized custom hosts block; config retained' unless before.scan(ANCHOR).size == 1
    after = before.sub(ANCHOR, ANCHOR + "      files:\n" + FILES.map { |f| "        - \"#{f}\"\n" }.join)
    expected = Marshal.load(Marshal.dump(cfg))
    expected['plugins'].find { |p| p['tag'] == 'hosts' }['args']['files'] = FILES.dup
    parsed = YAML.safe_load(after, permitted_classes: [Symbol], aliases: true)
    raise ArgumentError, 'Unexpected YAML semantic change' unless parsed == expected
    backup = path + '.before-lan-hosts-v1'
    raise ArgumentError, 'Refusing a symlink backup' if File.symlink?(backup)
    unless File.exist?(backup)
      File.open(backup, File::WRONLY | File::CREAT | File::EXCL, 0600) { |file| file.write(before) }
    end
    atomic_write(path, after, File.stat(path).mode & 0777)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    case ARGV.shift
    when 'sync'
      source = ARGV.shift || '/etc/AdGuardHome/AdGuardHome.yaml'
      output = ARGV.shift || '/etc/mosdns/rule/adguard-lan-hosts.txt'
      user_hosts = ARGV.shift || '/etc/mosdns/rule/hosts.txt'
      count = PersonalLanHosts.sync(source, output, user_hosts)
      puts "Local DNS mirror verified: #{count} exact IPv4 records"
    when 'configure'
      PersonalLanHosts.configure(ARGV.shift || '/etc/mosdns/config_custom.yaml')
      puts 'Custom MosDNS hosts loading verified'
    else
      raise ArgumentError, 'Usage: sync-adguard-hosts.rb sync [source output user-hosts] | configure [config]'
    end
  rescue Psych::Exception
    warn 'Invalid AdGuard/MosDNS YAML; previous configuration retained'
    exit 1
  rescue ArgumentError, SystemCallError => error
    warn "Local DNS preparation failed: #{error.message}"
    exit 1
  end
end
