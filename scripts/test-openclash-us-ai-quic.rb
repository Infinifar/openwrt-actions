#!/usr/bin/env ruby
require 'yaml'
require 'tmpdir'
require 'rbconfig'

root = File.expand_path('..', __dir__)
helper = File.join(root, 'app_config/etc/openclash/custom/openclash_ai_policy.rb')
profiles = Dir[File.join(root, 'app_config/etc/openclash/config/*Rule*.yaml')]
raise 'expected three profiles' unless profiles.size == 3
expected_group = {
  'name' => 'US-AI',
  'icon' => 'https://cdn.jsdelivr.net/gh/Koolson/Qure@master/IconSet/Color/United_States.png',
  'type' => 'select', 'include-all-providers' => true, 'include-all-proxies' => true,
  'filter' => '^(?=.*美国圣何塞)(?=.*[567]).*$', 'empty-fallback' => 'REJECT'
}
guards = nil
checks = 0
Dir.mktmpdir('openclash-us-ai-quic-') do |dir|
  profiles.each do |source|
    original = YAML.load_file(source, aliases: true)
    groups = original.fetch('proxy-groups')
    raise 'US-AI must be a single manual filtered leaf group' unless groups.select { |g| g['name'] == 'US-AI' } == [expected_group]
    %w[AI Google].each do |name|
      group = groups.find { |g| g['name'] == name }
      raise "missing optional US-AI choice: #{name}" unless group['proxies'].last == 'US-AI'
      raise "US-AI silently changed default: #{name}" if group['proxies'].first == 'US-AI'
    end
    current_guards = original.fetch('rules').first(5)
    guards ||= current_guards
    raise 'profile QUIC policies differ' unless guards == current_guards
    raise 'QUIC guard escaped domain/UDP/443 scope' unless guards.all? do |rule|
      rule.start_with?('AND,((NETWORK,UDP),(DST-PORT,443),') && rule.end_with?(',REJECT-DROP') &&
        !rule.match?(/(?:GEOIP|IP-CIDR|IP-ASN|RULE-SET|PROCESS-NAME),/)
    end
    %w[google openai anthropic github-copilot].each do |category|
      raise "missing domain category #{category}" unless guards.include?("AND,((NETWORK,UDP),(DST-PORT,443),(GEOSITE,#{category})),REJECT-DROP")
    end
    raise 'Antigravity/Copilot fallback missing' unless guards.last.include?('(DOMAIN-SUFFIX,antigravity.google)') && guards.last.include?('(DOMAIN-SUFFIX,copilot.microsoft.com)')
    raise 'global UDP/443 reject is forbidden' if original['rules'].include?('AND,((NETWORK,UDP),(DST-PORT,443)),REJECT-DROP')
    path = File.join(dir, 'profile.yaml')
    File.write(path, File.read(source))
    File.chmod(0o600, path)
    raise 'overwrite failed' unless system(RbConfig.ruby, helper, path)
    overwritten = YAML.load_file(path, aliases: true)
    raise 'OpenAI routing shadows QUIC guard' unless overwritten['rules'].first(5) == guards
    raise 'unrelated source rules changed' unless overwritten['rules'].drop(11) == original['rules'].drop(5)
    raise 'US-AI override diverges' unless overwritten['proxy-groups'].find { |g| g['name'] == 'US-AI' } == expected_group
    raise 'atomic replacement changed mode' unless File.stat(path).mode & 0o777 == 0o600
    bytes = File.binread(path)
    raise 'overwrite failed on repeat' unless system(RbConfig.ruby, helper, path)
    raise 'overwrite is not byte-idempotent' unless File.binread(path) == bytes
    checks += 1
  end
  legacy = YAML.load_file(profiles.first, aliases: true)
  legacy['proxy-groups'].reject! { |g| g['name'] == 'US-AI' }
  legacy['proxy-groups'].each { |g| g['proxies']&.delete('US-AI') }
  legacy['rules'] -= guards
  path = File.join(dir, 'legacy.yaml')
  File.write(path, YAML.dump(legacy))
  raise 'old profile migration failed' unless system(RbConfig.ruby, helper, path)
  fixed = YAML.load_file(path, aliases: true)
  raise 'old profile group not restored' unless fixed['proxy-groups'].find { |g| g['name'] == 'US-AI' } == expected_group
  raise 'old profile guard not restored' unless fixed['rules'].first(5) == guards
  raise 'old AI default changed' unless fixed['proxy-groups'].find { |g| g['name'] == 'AI' }['proxies'].first.split.last == 'US'
  checks += 1
end
filter = Regexp.new(expected_group.fetch('filter'))
%w[美国圣何塞05 美国圣何塞06 美国圣何塞07 美国圣何塞15 5-美国圣何塞 美国圣何塞01-0.5倍].each do |name|
  raise "literal inclusion filter rejected #{name}" unless filter.match?(name)
  checks += 1
end
%w[美国圣何塞01 美国圣何塞02 美国圣何塞04 美国圣何塞08 美国洛杉矶05 日本圣何塞05 美国圣何塞].each do |name|
  raise "filter admitted #{name}" if filter.match?(name)
  checks += 1
end
provider = YAML.load_file(File.join(root, 'app_config/etc/openclash/proxy_provider/Subscribe.yaml'), aliases: true)
names = Array(provider['proxies']).map { |p| p.fetch('name') }
raise 'filter disagrees with literal user conditions' unless names.grep(filter) == names.select { |n| n.include?('美国圣何塞') && n.match?(/[567]/) }
raise 'temporary override files remain' unless Dir.glob(File.join(root, 'app_config/etc/openclash/config/*.ai-policy.*')).empty?
puts "US-AI/QUIC regression tests passed: #{checks} fixtures; #{names.grep(filter).size} current matching leaves"
