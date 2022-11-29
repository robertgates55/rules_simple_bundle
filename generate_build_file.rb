#!/usr/bin/env ruby
# frozen_string_literal: true

BUILD_HEADER = <<~MAIN_TEMPLATE
  load("@rules_pkg//:pkg.bzl", "pkg_tar")
  package(default_visibility = ["//visibility:public"])

MAIN_TEMPLATE

LOCAL_GEM_TEMPLATE = <<~LOCAL_GEM_TEMPLATE
  genrule(
    name = "{name}-gem-install",
    srcs = [],
    exec_tools = {dependencies},
    outs = ["{name}.tar.gz"],
    cmd = """
      export BUILD_HOME=$$PWD
      export GEM_HOME=$$BUILD_HOME/gem
      mkdir -p $$GEM_HOME

      # Unpack dependencies
      for tarball in {dep_tars}; do
        tar -xzf $$tarball -C $$GEM_HOME
      done

      cd $$BUILD_HOME
      tar -czf $@ -C $$GEM_HOME . >/dev/null
    """,
    message = "Installing gem: {name}:{version}",
    visibility = ["//visibility:public"],
  )
LOCAL_GEM_TEMPLATE

GEM_TEMPLATE = <<~GEM_TEMPLATE
  genrule(
    name = "{name}-gem-fetch",
    srcs = [],
    outs = ["{gem_name}.gem"],
    cmd = """
      TARGET_PLATFORM="x86_64-linux"
      gem fetch --platform $$TARGET_PLATFORM --no-prerelease --source {source} --version {version} {name} >/dev/null
      mv {name}-{version}*.gem $@ >/dev/null
    """,
    message = "Fetching gem: {name}:{version}",
    visibility = ["//visibility:public"],
  )

  genrule(
    name = "{name}-gem-install",
    srcs = [":{name}-gem-fetch"],
    exec_tools = {dependencies},
    outs = ["{name}.tar.gz"],
    cmd = """
      export BUILD_HOME=$$PWD
      cp $< $$BUILD_HOME

      export GEM_HOME=$$BUILD_HOME/gem
      mkdir -p $$GEM_HOME

      # Unpack dependencies
      for tarball in {dep_tars}; do
        tar -xzf $$tarball -C $$GEM_HOME
      done
      
      TARGET_PLATFORM="x86_64-linux"
      GEM_PLATFORM=$$(gem specification {name}-{version}.gem --yaml | grep 'platform: ' | awk '{print $$2}')
      ENV_PLATFORM=$$(gem environment platform)
      TARGET_PLATFORM_MATCH=$$(echo $$ENV_PLATFORM | grep $$TARGET_PLATFORM >/dev/null; echo $$?)
      GEM_PLATFORM_MATCH=$$(echo $$ENV_PLATFORM | grep $$GEM_PLATFORM >/dev/null; echo $$?)
      
      GEM_NO_EXTENSIONS=$$(gem specification {name}-{version}.gem extensions | sed '1d;$$d' | wc -l) # 0 = no extensions

      if [ "$${TARGET_PLATFORM_MATCH}" -eq "0" ] || ( [ "$${GEM_NO_EXTENSIONS}" -eq "0" ] && [ "$${GEM_PLATFORM_MATCH}" -eq "0" ] )
      then
        gem install --platform $$TARGET_PLATFORM --no-document --no-wrappers --ignore-dependencies --local --version {version} {name} >/dev/null 2>&1
        # Symlink all the bin files
        cd $$GEM_HOME
        find ./bin -type l -exec sh -c 'if [[ $$(readlink $$0) == /* ]]; then (export TARGET_ABS=$$(readlink $$0) REPLACE="$${PWD}/"; rm $$0; ln -s ../"$${TARGET_ABS/"$${REPLACE}"/}" $$0); fi' {} + || true
        # Clean up files we don't need in the bundle
        rm -rf $$GEM_HOME/wrappers $$GEM_HOME/environment $$GEM_HOME/cache/{name}-{version}*.gem
      else
        echo ++++ {name} Incompatible platform or extensions to build - keep the gem for later install
        mkdir -p $$GEM_HOME/cache
        mv $$BUILD_HOME/{name}-{version}.gem $$GEM_HOME/cache
        ln -s {name}-{version}.gem $$GEM_HOME/cache/{name}-{version}-$$TARGET_PLATFORM.gem
      fi

      cd $$BUILD_HOME
      tar -czf $@ -C $$GEM_HOME . >/dev/null
    """,
    message = "Installing gem: {name}:{version}",
    visibility = ["//visibility:public"],
  )

GEM_TEMPLATE

GEM_GROUP = <<~GEM_GROUP
  pkg_tar(
    name = "gems-{group}",
    deps = {group_gem_installs},
    owner = "1000.1000",
    package_dir = "/vendor/bundle/ruby/{ruby_version}"
  )

GEM_GROUP

ALL_GEMS = <<~ALL_GEMS
  pkg_tar(
    name = "gems",
    deps = {groups}
  )

ALL_GEMS

require 'bundler'
require 'json'
require 'stringio'
require 'fileutils'
require 'tempfile'

class BundleBuildFileGenerator
  attr_reader :build_file, :gemfile, :gemfile_lock

  def initialize(build_file: 'BUILD.bazel',
                 gemfile: 'Gemfile',
                 gemfile_lock: 'Gemfile.lock')
    @build_file     = build_file
    @gemfile        = gemfile
    @gemfile_lock   = gemfile_lock
  end

  def generate!
    # when we append to a string many times, using StringIO is more efficient.
    template_out = StringIO.new
    template_out.puts BUILD_HEADER

    # Register bundler first
    register_bundler(template_out)

    # Register all the gems
    bundle = Bundler::LockfileParser.new(Bundler.read_file(gemfile_lock))
    bundle.specs.each { |spec| register_gem(spec, template_out) }

    # Collect up the groups in the gemfile, and their gems
    bundle_def    = Bundler::Definition.build(gemfile, gemfile_lock, {})
    gems_by_group = bundle_def.groups.map{
      |g| { g => bundle_def
                  .dependencies
                  .select{|dep| dep.groups.include? g.to_sym}
                  .map(&:name)
      }
    }.reduce Hash.new, :merge

    # Create tarballs with the gem groups
    gems_by_group.each do |key, value|
      template_out.puts GEM_GROUP
                          .gsub('{group}', key.to_s)
                          .gsub('{group_gem_installs}', value.map{|s| ":#{s}-gem-install"}.compact.to_s)
                          .gsub('{ruby_version}', RUBY_VERSION)
    end

    template_out.puts ALL_GEMS
                        .gsub('{groups}', bundle_def.groups.map{|g| ":gems-#{g}"}.to_s)
    ::File.open(build_file, 'w') { |f| f.puts template_out.string }
  end

  private

  def register_gem(spec, template_out)
    template_to_use = (spec.source.path?) ? LOCAL_GEM_TEMPLATE : GEM_TEMPLATE

    template_out.puts template_to_use
                        .gsub('{name}', spec.name)
                        .gsub('{gem_name}', "#{spec.name}-#{spec.version}")
                        .gsub('{dependencies}', spec.dependencies.map{|spec| "#{spec.name}-gem-install"}.to_s)
                        .gsub('{dep_tars}', spec.dependencies.map{|spec| "$(location :#{spec.name}-gem-install)"}.join(' '))
                        .gsub('{version}', spec.version.version)
                        .gsub('{source}', spec.source.path? ? '' : spec.source.remotes.first.to_s)
                        .gsub('{ruby_version}', RUBY_VERSION)
  end

  def register_bundler(template_out)
    template_out.puts GEM_TEMPLATE
                        .gsub('{name}', 'bundler')
                        .gsub('{gem_name}', "bundler-#{Bundler::VERSION}")
                        .gsub('{dependencies}', "[]")
                        .gsub('{dep_tars}', "")
                        .gsub('{version}', Bundler::VERSION)
                        .gsub('{source}', 'https://rubygems.org')
                        .gsub('{ruby_version}', RUBY_VERSION)
  end
end

# ruby ./generate_build_file.rb "BUILD.bazel" "Gemfile.lock"
if $0 == __FILE__

  build_file, gemfile, gemfile_lock, * = *ARGV

  BundleBuildFileGenerator.new(build_file:     build_file,
                               gemfile:   gemfile,
                               gemfile_lock:   gemfile_lock).generate!
end