#!/usr/bin/env ruby
# frozen_string_literal: true

BASIC_BUILD_FILE = <<~BASIC_BUILD_FILE
  package(default_visibility = ["//visibility:public"])
  load("@rules_simple_maven//tools:mvn.bzl", "mvn")

  mvn(
      name = "{name}",
      pom = "pom.xml",
      srcs = glob([
          "src/main/**/*",
      ]),
  )
BASIC_BUILD_FILE

BUILD_HEADER = <<~BUILD_HEADER
  load("@rules_pkg//:pkg.bzl", "pkg_tar")
  package(default_visibility = ["//visibility:public"])

BUILD_HEADER

PACKAGE_TEMPLATE = <<~PACKAGE_TEMPLATE
  filegroup(
    name = "{name}_deps",
    srcs = {dependencies},
  )

PACKAGE_TEMPLATE
require 'xmlhasher'
require 'stringio'
require 'pathname';

DUCO_PREFIXES=['duco.cube', 'co.du']

def safe_command(command)
  output = `#{command}`
  unless $?.success?
    raise "Command returned non-zero: #{command}"
  end
  output
end

def get_all_packages(root)
  all_poms = Dir.glob("#{root}/**/pom.xml")
  all_poms
    .map { |pom| parse_pom_into_package(pom) }
    .each { |package| package[:location] = safe_relative_path(root, package[:pom]) }
end

def parse_pom_into_package(pom)
  pom_hash = XmlHasher.parse(File.new(pom))
  package = {}
  package[:pom] = pom
  package[:artifact_id] = get_artifact_from_pom_hash(pom_hash)
  package[:group_id] = get_group_from_pom_hash(pom_hash)
  package[:parent] = get_parent_from_pom_hash(pom_hash)
  package[:dependencies] = get_duco_deps(get_deps_from_pom_hash(pom_hash))
  package
end

def get_artifact_location(packages, group_lookup, artifact_lookup)
  output = packages
    .select{ |artifact| artifact[:group_id] == group_lookup}
    .select{ |artifact| artifact[:artifact_id] == artifact_lookup}
    .map{ |artifact| artifact[:location] }
    .first
  output.empty? ? 'src' : "src/#{output}"
end

def get_group_from_pom_hash(pom_hash)
  if !pom_hash[:project][:groupId].nil?
    group = pom_hash[:project][:groupId]
  elsif !pom_hash[:project][:parent][:groupId].nil?
    group = pom_hash[:project][:parent][:groupId]
  else
    group = "co.du"
  end
  group
end

def get_artifact_from_pom_hash(pom_hash)
  pom_hash[:project][:artifactId]
end

def get_parent_from_pom_hash(pom_hash)
  parent = {}
  if !pom_hash[:project][:parent].nil?
    parent = pom_hash[:project][:parent] unless pom_hash[:project][:parent].nil?
    parent = {:group_id => parent[:groupId], :artifact_id => parent[:artifactId]}
  end
  parent
end

def get_deps_from_pom_hash(pom_hash)
  if pom_hash[:project][:dependencies].nil?
    deps = []
  elsif pom_hash[:project][:dependencies][:dependency].is_a? Array
    deps = pom_hash[:project][:dependencies][:dependency]
  else
    deps = [ pom_hash[:project][:dependencies][:dependency] ]
  end
  deps.map{ |dep| { :artifact_id => dep[:artifactId], :group_id => dep[:groupId]}}
end

def get_duco_deps(deps)
  deps.select{ |dep| dep[:group_id].start_with?(*DUCO_PREFIXES) }
end

def safe_package_name(package)
  package_name = File.join('src', package[:location])
  package_name.chomp('/').gsub('/','_')
end

def safe_relative_path(root, pom)
  File.dirname(Pathname.new(pom).relative_path_from(Pathname.new(root))).gsub('.','')
end

# ruby ./parse_pom.rb "pom.xml"
if $0 == __FILE__
  root_pom, * = *ARGV

  # when we append to a string many times, using StringIO is more efficient.
  template_out = StringIO.new
  template_out.puts BUILD_HEADER

  # Recurse from the root pom - discover all poms & all packages
  all_packages = get_all_packages(File.dirname(root_pom))
  root_package = all_packages.select{|p| p[:location].empty? }.first

  all_packages.each do |package|

    # Get all deps
    deps = package[:dependencies] + [package[:parent]]

    # Map to bazel targets
    dep_targets = deps
                    .reject { |c| c.empty? }
                    .map{|dep| get_artifact_location(all_packages, dep[:group_id], dep[:artifact_id])}
                    .map{|dep_location| "@cube//#{dep_location}:mvn"}
                    .uniq
    dep_targets = [":generate_maven_build_file.rb"] if dep_targets.empty?

    # Write the package deps
    template_out.puts PACKAGE_TEMPLATE
                    .gsub('{name}', safe_package_name(package))
                    .gsub('{dependencies}', dep_targets.to_s)

    location = File.dirname(package[:pom])
    build_file = File.join(location,'BUILD')
    ::File.open(build_file, 'w') {
      |f| f.puts BASIC_BUILD_FILE
                   .gsub('{name}', location.split('/').last)
    } unless File.exist? build_file
  end

  ::File.open('BUILD.bazel', 'w') { |f| f.puts template_out.string }
end