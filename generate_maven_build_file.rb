#!/usr/bin/env ruby
# frozen_string_literal: true

BASIC_BUILD_FILE = <<~BASIC_BUILD_FILE
  package(default_visibility = ["//visibility:public"])
  load("@rules_simple_maven//tools:mvn_package.bzl", "mvn_package")

  mvn_package(
      name = "mvn-package",
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
MVN_EXE='mvn'

def safe_command(command)
  output = `#{command}`
  unless $?.success?
    raise "Command returned non-zero: #{command}"
  end
  output
end

def get_all_packages(root)
  all_poms = Dir.glob("#{root}/**/pom.xml")
  all_poms.map { |pom| {
    :artifact_id  => get_artifact_from_pom(pom),
    :group_id     => get_group_from_pom(pom),
    :parent       => get_parent_from_pom(pom),
    :location     => safe_relative_path(root, pom),
    :pom          => pom,
    :dependencies => get_duco_deps(get_deps_from_pom(pom)).map{ |dep| { :artifact_id => dep[:artifactId], :group_id => dep[:groupId]}}
  }}
end

def get_artifact_location(packages, group_lookup, artifact_lookup)
  output = packages
    .select{ |artifact| artifact[:group_id] == group_lookup}
    .select{ |artifact| artifact[:artifact_id] == artifact_lookup}
    .map{ |artifact| artifact[:location] }
    .first
  output.empty? ? 'src' : "src/#{output}"
end

def get_artifact_pom(packages, group_lookup, artifact_lookup)
  output = packages
             .select{ |artifact| artifact[:group_id] == group_lookup}
             .select{ |artifact| artifact[:artifact_id] == artifact_lookup}
             .map{ |artifact| artifact[:pom] }
             .first
  output
end


def get_group_from_pom(pom)
  pom_hash = XmlHasher.parse(File.new(pom))
  if !pom_hash[:project][:groupId].nil?
    group = pom_hash[:project][:groupId]
  elsif !pom_hash[:project][:parent][:groupId].nil?
    group = pom_hash[:project][:parent][:groupId]
  else
    group = "co.du"
  end
  group
end

def get_all_parent_poms(packages, package)
  parent_poms = []
  parent = package[:parent]
  while parent
    parent_poms << get_artifact_pom(packages, parent[:group_id], parent[:artifact_id]) unless parent.nil?
    parent = packages
      .select{ |artifact| artifact[:group_id] == parent[:group_id]}
      .select{ |artifact| artifact[:artifact_id] == parent[:artifact_id]}
      .map{ |artifact| artifact[:parent] }
      .first
  end
  parent_poms
end

def get_artifact_from_pom(pom)
  pom_hash = XmlHasher.parse(File.new(pom))
  pom_hash[:project][:artifactId]
end

def get_deps_from_pom(pom)
  pom_hash = XmlHasher.parse(File.new(pom))
  get_deps_from_pom_hash(pom_hash)
end

def get_parent_from_pom(pom)
  pom_hash = XmlHasher.parse(File.new(pom))
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
  deps
end

def get_duco_deps(deps)
  deps.select{ |dep| dep[:groupId].start_with?(*DUCO_PREFIXES) }
end

def bazel_target_name(package)
  group_name = package[:group_id].gsub(/[.]/,'-')
  artifact_name = package[:artifact_id].gsub(/[.]/,'-')
  target_name = group_name
  target_name =+ "_#{artifact_name}" unless artifact_name.nil?
  target_name
end

def safe_relative_path(root, pom)
  File.dirname(Pathname.new(pom).relative_path_from(Pathname.new(root))).gsub('.','')
end

# ruby ./parse_pom.rb "pom.xml"
if $0 == __FILE__
  root, * = *ARGV

  # when we append to a string many times, using StringIO is more efficient.
  template_out = StringIO.new
  template_out.puts BUILD_HEADER

  all_packages = get_all_packages File.dirname(root)

  all_packages.each do |package|
    deps = package[:dependencies]
             .map{|dep| "@cube//#{get_artifact_location(all_packages, dep[:group_id], dep[:artifact_id])}:mvn-package"}

    parent_poms = get_all_parent_poms(all_packages, package).uniq.reject { |c| c.nil? }
    deps.concat(parent_poms.map{ |pom| "@cube//src#{safe_relative_path(root, pom)}:mvn-package" })
    deps.append '//:generate_maven_build_file.rb'

    package_name = package[:location].empty? ? 'src' : File.join('src', package[:location]).gsub('/','_')

    template_out.puts PACKAGE_TEMPLATE
                        .gsub('{name}', package_name)
                        .gsub('{dependencies}', deps.uniq.to_s)

    location = File.dirname(package[:pom])
    build_file = File.join(location,'BUILD')
    ::File.open(build_file, 'w') {
      |f| f.puts BASIC_BUILD_FILE
                   .gsub('{name}', bazel_target_name(package))
                   .gsub('{dep_locations}', package[:dependencies].size > 0 ? "$(locations @src_maven_tree//:#{bazel_target_name(package)}_deps)" : "")
    } unless File.exist? build_file
  end

  ::File.open('BUILD.bazel', 'w') { |f| f.puts template_out.string }
end