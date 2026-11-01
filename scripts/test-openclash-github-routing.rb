#!/usr/bin/env ruby
require 'yaml'
require 'tmpdir'
require 'rbconfig'

root = File.expand_path('..', __dir__)
helpers = %w[ai docker github].map { |name| File.join(root, "app_config/etc/openclash/custom/openclash_#{name}_policy.rb") }
profiles = Dir[File.join(root, 'app_config/etc/openclash/config/*Rule*.yaml')].sort
raise 'expected three profiles' unless profiles.size == 3
url = 'https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/GitHub/GitHub.yaml'
domains = %w[github.com githubusercontent.com githubassets.com githubapp.com github.io github.dev github.blog githubstatus.com]
owned = ['DOMAIN,api.githubcopilot.com,GitHub', 'DOMAIN-SUFFIX,ghcr.io,Docker'] +
        domains.map { |domain| "DOMAIN-SUFFIX,#{domain},GitHub" } + ['RULE-SET,GitHub,GitHub']
checks = 0
Dir.mktmpdir('openclash-github-test-') do |dir|
  path = File.join(dir, 'profile.yaml')
  apply = lambda do |data, success = true|
    File.write(path, YAML.dump(data))
    File.chmod(0o600, path)
    before = File.binread(path)
    actual = system(RbConfig.ruby, helpers.last, path, err: File::NULL)
    raise 'unexpected helper exit status' unless actual == success
    raise 'failed policy changed profile bytes' if !success && File.binread(path) != before
    YAML.safe_load_file(path, aliases: true)
  end
  profiles.each do |source|
    original = YAML.safe_load_file(source, aliases: true)
    groups = original.fetch('proxy-groups')
    github = groups.find { |group| group['name'] == 'GitHub' }
    raise 'manual GitHub selector/default missing' unless github && github['type'] == 'select' && github['proxies'].first == 'Proxy'
    raise 'GitHub selector missing US-AI' unless github['proxies'].count('US-AI') == 1
    known = groups.map { |group| group['name'] }
    raise 'GitHub selector references nonexistent group' unless (github['proxies'] - known).empty?
    provider = original.fetch('rule-providers').fetch('GitHub')
    raise 'GitHub public provider mismatch' unless provider.values_at('type', 'behavior', 'format', 'url', 'path', 'interval') == ['http', 'classical', 'yaml', url, './rule_provider/GitHub.yaml', 43_200]
    rules = original.fetch('rules')
    raise 'source GitHub block order mismatch' unless rules[8, owned.size] == owned
    raise 'GitHub after broad direct rules' unless rules.index(owned.last) < rules.index('RULE-SET,CustomDirect,Domestic')
    current = apply.call(original)
    raise 'complete source should not change semantically' unless current == original
    before = File.binread(path)
    raise 'repeat helper failed' unless system(RbConfig.ruby, helpers.last, path)
    raise 'helper not byte-idempotent' unless before == File.binread(path)
    raise 'file mode changed' unless File.stat(path).mode & 0o777 == 0o600
    checks += 1

    # Real overwrite order, twice: retain QUIC5/OpenAI6/Google3 then GitHub11.
    2.times do
      helpers.each { |helper| raise 'combined overwrite failed' unless system(RbConfig.ruby, helper, path) }
      current = YAML.safe_load_file(path, aliases: true)
      %w[proxy-groups proxy-providers dns sniffer secret profile].each do |key|
        raise "unrelated setting changed: #{key}" unless current[key] == original[key]
      end
      raise 'QUIC rules changed' unless current['rules'].first(5) == rules.first(5)
      raise 'Google prefix changed' unless current['rules'][11, 3] == rules[5, 3]
      raise 'final GitHub priority changed' unless current['rules'][14, owned.size] == owned
      expected_unrelated = rules.reject { |rule| owned.include?(rule) }
      current_unrelated = current['rules'].reject { |rule| owned.include?(rule) }
      openai = %w[openai.com chatgpt.com oaistatic.com oaiusercontent.com openai.com.cdn.cloudflare.net chatgpt.com.cdn.cloudflare.net].map { |domain| "DOMAIN-SUFFIX,#{domain},AI" }
      raise 'unrelated routing changed' unless current_unrelated == expected_unrelated.first(5) + openai + expected_unrelated.drop(5)
      checks += 1
    end
  end
  fixture = YAML.safe_load_file(profiles.first, aliases: true)
  fixture['rules'] = fixture['rules'].reject { |rule| owned.include?(rule) } + owned.reverse + owned
  fixture['rule-providers']['GitHub']['url'] = "https://ghproxy.wegod.cc/#{url}"
  fixed = apply.call(fixture)
  raise 'legacy provider URL not repaired' unless fixed.dig('rule-providers', 'GitHub', 'url') == url
  raise 'rules not deduplicated/repositioned' unless fixed['rules'][8, owned.size] == owned && owned.all? { |rule| fixed['rules'].count(rule) == 1 }
  checks += 1

  collision = Marshal.load(Marshal.dump(fixture))
  collision['rule-providers']['GitHub']['url'] = 'https://example.invalid/user-rules.yaml'
  apply.call(collision, false)
  checks += 1
  collision = Marshal.load(Marshal.dump(fixture))
  collision['rules'] << 'RULE-SET,GitHub,MyCustomPolicy'
  apply.call(collision, false)
  checks += 1

  missing = Marshal.load(Marshal.dump(fixture))
  missing['rule-providers'].delete('GitHub')
  fixed = apply.call(missing)
  raise 'missing GitHub provider not installed' unless fixed.dig('rule-providers', 'GitHub', 'url') == url
  checks += 1

  no_docker = Marshal.load(Marshal.dump(fixture))
  no_docker['proxy-groups'].reject! { |group| group['name'] == 'Docker' }
  no_docker['rules'].reject! { |rule| rule.end_with?(',Docker') }
  fixed = apply.call(no_docker)
  raise 'dangling Docker rule introduced' if fixed['rules'].any? { |rule| rule.end_with?(',Docker') }
  checks += 1

  untouched = "# do not invent groups\nproxy-groups: []\nrules: ['MATCH,DIRECT']\n"
  File.write(path, untouched)
  raise 'unrelated profile failed' unless system(RbConfig.ruby, helpers.last, path)
  raise 'unrelated profile bytes changed' unless File.binread(path) == untouched
  checks += 1
  raise 'temporary policy files remain' unless Dir[File.join(dir, '*.github-policy.*')].empty?
end
puts "GitHub routing regression tests passed: #{checks} fixtures; dedicated GitHub/MCP, Docker registry retained, no selection/IPv6 changes"
