#!/usr/bin/env ruby
require 'yaml'
require 'tmpdir'
require 'rbconfig'

root = File.expand_path('..', __dir__)
helper = File.join(root, 'app_config/etc/openclash/custom/openclash_ai_policy.rb')
profiles = Dir[File.join(root, 'app_config/etc/openclash/config/*Rule*.yaml')]
raise 'expected three profiles' unless profiles.size == 3
domains = %w[antigravity.google gemini.google.com generativelanguage.googleapis.com]
priority = domains.map { |domain| "DOMAIN-SUFFIX,#{domain},Google" }
checks = 0
custom = YAML.safe_load_file(File.join(root, 'app_config/etc/openclash/custom/openclash_custom_rules.list'), aliases: true)
raise 'custom Google fallbacks missing' unless (priority - custom.fetch('rules')).empty?
Dir.mktmpdir('openclash-google-test-') do |dir|
  profiles.each_with_index do |source, index|
    original = YAML.safe_load_file(source, aliases: true)
    rules = original.fetch('rules')
    raise 'Gemini still points to AI' unless rules.include?('RULE-SET,Gemini,Google') && !rules.include?('RULE-SET,Gemini,AI')
    raise 'Google service fallbacks must follow unchanged QUIC guards' unless rules[5, 3] == priority
    path = File.join(dir, "profile-#{index}.yaml")
    File.write(path, File.read(source))
    2.times do
      raise 'Google overwrite failed' unless system(RbConfig.ruby, helper, path)
      current = YAML.safe_load_file(path, aliases: true)
      raise 'Google migration changed selectors or subscriptions' unless %w[proxy-groups proxy-providers dns secret].all? { |key| current[key] == original[key] }
      raise 'QUIC scope/order changed' unless current.fetch('rules').first(5) == rules.first(5)
      raise 'Google safety net missing' unless current.fetch('rules')[11, 3] == priority
      raise 'Google migration changed unrelated rules' unless current.fetch('rules').drop(11) == rules.drop(5)
      checks += 1
    end
  end
  legacy = YAML.safe_load_file(profiles.first, aliases: true)
  legacy_rules = ['RULE-SET,Gemini,AI', 'DOMAIN-SUFFIX,antigravity.google,AI',
                  'DOMAIN,gemini.google.com,AI', 'DOMAIN,api.gemini.google.com,AI',
                  'DOMAIN,generativelanguage.googleapis.com,AI', 'DOMAIN-KEYWORD,generativelanguage,AI']
  controls = ['DOMAIN,gemini.example.invalid,AI', 'DOMAIN-SUFFIX,claude.ai,AI',
              'DOMAIN-SUFFIX,chatgpt.com,AI', 'DOMAIN-SUFFIX,gemini.example.invalid,DIRECT']
  legacy['rules'] = legacy_rules + controls + legacy.fetch('rules')
  path = File.join(dir, 'legacy.yaml')
  File.write(path, YAML.dump(legacy))
  raise 'legacy Google migration failed' unless system(RbConfig.ruby, helper, path)
  current = YAML.safe_load_file(path, aliases: true)
  expected = legacy_rules.map { |rule| rule.sub(/,AI\z/, ',Google') }
  raise 'legacy AI routes survived' unless (legacy_rules & current.fetch('rules')).empty?
  raise 'legacy Google routes missing' unless (expected - current.fetch('rules')).empty?
  raise 'unrelated AI/direct routes changed' unless (controls - current.fetch('rules')).empty?
  raise 'duplicate Gemini provider route' unless current.fetch('rules').count('RULE-SET,Gemini,Google') == 1
  bytes = File.binread(path)
  raise 'legacy repeat failed' unless system(RbConfig.ruby, helper, path)
  raise 'Google migration is not idempotent' unless File.binread(path) == bytes
  checks += 1

  missing_google = YAML.safe_load_file(profiles.first, aliases: true)
  missing_google['proxy-groups'].reject! { |group| group['name'] == 'Google' }
  missing_google['rules'].reject! { |rule| rule.end_with?(',Google') }
  missing_google['rules'].unshift('RULE-SET,Gemini,AI')
  path = File.join(dir, 'missing-google.yaml')
  File.write(path, YAML.dump(missing_google))
  raise 'missing Google group fixture failed' unless system(RbConfig.ruby, helper, path)
  current = YAML.safe_load_file(path, aliases: true)
  raise 'dangling Google references introduced' if current.fetch('rules').any? { |rule| rule.end_with?(',Google') }
  checks += 1

  missing_provider = YAML.safe_load_file(profiles.first, aliases: true)
  missing_provider['rule-providers'].delete('Gemini')
  missing_provider['rules'].reject! { |rule| rule.start_with?('RULE-SET,Gemini,') }
  path = File.join(dir, 'missing-provider.yaml')
  File.write(path, YAML.dump(missing_provider))
  raise 'missing Gemini provider fixture failed' unless system(RbConfig.ruby, helper, path)
  current = YAML.safe_load_file(path, aliases: true)
  raise 'undefined Gemini provider reference introduced' if current.fetch('rules').any? { |rule| rule.start_with?('RULE-SET,Gemini,') }
  checks += 1
end
puts "Google routing regression tests passed: #{checks} fixtures; Gemini/Antigravity use Google, unrelated AI and QUIC unchanged"
