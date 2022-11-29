
RULES_RUBY_WORKSPACE_NAME = "@rules_simple_bundle"
SCRIPT_BUILD_FILE_GENERATOR = "generate_build_file.rb"

def _bundle_fetch_impl(ctx):
    ctx.symlink(ctx.attr.gemfile, ctx.attr.gemfile.name)
    ctx.symlink(ctx.attr.gemfile_lock, ctx.attr.gemfile_lock.name)
    ctx.symlink(ctx.attr._generate_script, SCRIPT_BUILD_FILE_GENERATOR)
    for src in ctx.attr.srcs:
        ctx.symlink(src, src.name)
    generate_build_file(ctx)

bundle_fetch = repository_rule(
    implementation = _bundle_fetch_impl,
    attrs = {
        "gemfile": attr.label(
            allow_single_file = True,
        ),
        "gemfile_lock": attr.label(
            allow_single_file = True,
        ),
        "srcs": attr.label_list(
            allow_files = True,
        ),
        "_generate_script": attr.label(
            default = "%s//:%s" % (RULES_RUBY_WORKSPACE_NAME, SCRIPT_BUILD_FILE_GENERATOR),
        ),
    },
    doc = "Produces a BUILD file that downloads all the gemfile defined gems",
)

def generate_build_file(ctx):
    gemfile = ctx.attr.gemfile.name
    gemfile_lock = ctx.attr.gemfile_lock.name

    # Create the BUILD file to expose the gems to the WORKSPACE
    # USAGE: ./generate_build_file.rb BUILD.bazel Gemfile.lock
    args = [
        "ruby",
        "generate_build_file.rb",
        "BUILD.bazel",  # Bazel build file (can be empty)
        gemfile,
        gemfile_lock,  # Gemfile.lock where we list all direct and transitive dependencies
        ctx.name,  # Name of the target
    ]

    result = ctx.execute(args, quiet = False)
    if result.return_code:
        fail("build file generation failed: %s%s" % (result.stdout, result.stderr))