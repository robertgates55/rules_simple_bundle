RULES_MVN_WORKSPACE_NAME = "@rules_simple_maven"
SCRIPT_BUILD_FILE_GENERATOR = "generate_maven_build_file.rb"

def _maven_tree_impl(ctx):
    ctx.symlink(ctx.attr.root_pom, ctx.attr.root_pom.name)
    ctx.symlink(ctx.attr._generate_script, SCRIPT_BUILD_FILE_GENERATOR)
    for src in ctx.attr.srcs:
        ctx.symlink(src, src.name)
    generate_build_file(ctx)


maven_tree = repository_rule(
    implementation = _maven_tree_impl,
    attrs = {
        "root_pom": attr.label(
            allow_single_file = True,
        ),
        "srcs": attr.label_list(
            allow_files = True,
        ),
        "_generate_script": attr.label(
            default = "%s//:%s" % (RULES_MVN_WORKSPACE_NAME, SCRIPT_BUILD_FILE_GENERATOR),
        ),
    },
    doc = "Produces a BUILD file with all the maven package genrules",
)

def generate_build_file(ctx):
    root_pom = ctx.attr.root_pom

    # Create the BUILD file to expose the gems to the WORKSPACE
    # USAGE: ./generate_maven_build_file.rb root_pom package_pom
    args = [
        "ruby",
        SCRIPT_BUILD_FILE_GENERATOR,
        root_pom,
    ]
    result = ctx.execute(args, quiet = False)
    if result.return_code:
        fail("build file generation failed: %s%s" % (result.stdout, result.stderr))