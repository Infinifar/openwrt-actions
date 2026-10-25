#!/usr/bin/env ruby
# Shared by hosted GitHub CI and local checks; no gems or global monkey patches.
require 'yaml'
require 'tmpdir'
require 'rbconfig'

abort 'Ruby YAML capability missing: safe_load_file is required' unless YAML.respond_to?(:safe_load_file)
root = File.expand_path('..', __dir__)
if ENV['GITHUB_ACTIONS'] == 'true'
  expected = File.read(File.join(root, '.ruby-version')).strip
  abort "CI selected Ruby #{RUBY_VERSION}, expected #{expected}" unless RUBY_VERSION == expected
end
# Offline checks can also exercise older firmware/host Rubies. CI must use the
# explicitly selected toolchain, not silently fall back to apt's system Ruby.
loaders = %w[
  scripts/test-openclash-ai-policy.rb
  scripts/test-openclash-us-ai-quic.rb
  scripts/test-openclash-docker-policy.rb
  app_config/etc/openclash/custom/openclash_ai_policy.rb
  app_config/etc/openclash/custom/openclash_docker_policy.rb
]
loaders.each do |relative|
  source = File.read(File.join(root, relative), encoding: 'UTF-8')
  abort "Obsolete or unsafe YAML loader in #{relative}" if source.match?(/YAML\.(?:load_file|unsafe_load(?:_file)?)\s*\(/)
  abort "Expected safe YAML file loader in #{relative}" unless source.include?('YAML.safe_load_file(')
end

Dir.mktmpdir('ruby-yaml-capability-') do |directory|
  path = File.join(directory, 'fixture.yaml')
  source = "---\ndefaults: &defaults\n  mode: 'off'\n  enabled: false\n  label: 美国\ncopy:\n  <<: *defaults\n"
  File.binwrite(path, "\xEF\xBB\xBF".b + source.b)
  parsed = YAML.safe_load_file(path, aliases: true)
  expected = {'mode' => 'off', 'enabled' => false, 'label' => '美国'}
  abort 'YAML aliases/UTF-8/BOM/scalar round-trip failed' unless parsed['copy'] == expected
  File.write(path, YAML.dump(parsed))
  abort 'YAML dump/read round-trip failed' unless YAML.safe_load_file(path, aliases: true) == parsed

  File.write(path, "--- !ruby/object:Object {}\n")
  blocked = false
  begin
    YAML.safe_load_file(path, aliases: true)
  rescue Psych::DisallowedClass
    blocked = true
  end
  abort 'Unsafe Ruby object deserialization was accepted' unless blocked

  File.write(path, "copy: *missing\n")
  blocked = false
  begin
    YAML.safe_load_file(path, aliases: true)
  rescue Psych::BadAlias
    blocked = true
  end
  abort 'Undefined YAML alias was silently accepted' unless blocked

  File.write(path, "broken: [\n")
  blocked = false
  begin
    YAML.safe_load_file(path, aliases: true)
  rescue Psych::SyntaxError
    blocked = true
  end
  abort 'Malformed YAML was silently accepted' unless blocked
end
puts "Ruby YAML capability passed: Ruby #{RUBY_VERSION}, Psych #{Psych::VERSION}; aliases, UTF-8/BOM, scalar preservation and unsafe/malformed rejection"
