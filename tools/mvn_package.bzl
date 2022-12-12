load("@rules_pkg//:pkg.bzl", "pkg_tar")

def mvn_package(name, pom, srcs=[], deps=[], visibility = None):

    PACKAGE_NAME = native.package_name().replace("/","_")
    DEP_LOCATIONS = ["$(locations %s)" % d for d in deps] + ["$(locations @src_maven_tree//:%s_deps)" % PACKAGE_NAME]

    native.filegroup(
        name = "srcs",
        srcs = srcs,
    )

    native.genrule(
        name = "mvn-package",
        srcs = [
            pom,
            ":srcs",
            "@src_maven_tree//:%s_deps" % PACKAGE_NAME
        ] + deps,
        outs = ["%s.tar" % name],
        toolchains = ["@bazel_tools//tools/jdk:current_java_runtime"],
        local = False,
        cmd = """
            # Set the java for repeatability - see toolchains
            export JAVA_HOME=$$PWD/$(JAVABASE)

            # Set mvn repo & tar out envs
            MVN_LOCAL_REPO_DIR=$$PWD/maven_repo
            MVN_TARBALL=$$PWD/$@

            # Get the absolute path of this project's pom on disk
            # We use this later to symlink it in
            REAL_ABSOLUTE_PATH=$$(dirname $$(readlink -f $(location :pom.xml)))

            # Unpack dependencies into local mvn repo dir
            mkdir -p $$MVN_LOCAL_REPO_DIR
            for file in %s; do
                # Untar any tars
                if [[ $$file == *.tar ]]; then
                    tar -xzf $$file -C $$MVN_LOCAL_REPO_DIR
                fi
            done

            # Change into the directory with the main pom
            cd $$PWD/$$(dirname $(location :pom.xml))

            # Symlink madness - mostly for the input-formats code
            mkdir -p ./$$(dirname $$REAL_ABSOLUTE_PATH)
            ln -s $$REAL_ABSOLUTE_PATH ./$$(dirname $$REAL_ABSOLUTE_PATH)

            # Maven install to the local maven repo
            # Skip tests and skip compiling tests
            # Batch mode, quiet mode, non-recursive mode
            mvn -B -q -N install -Dmaven.test.skip=true -DskipTests -Dmaven.repo.local=$$MVN_LOCAL_REPO_DIR

            # Tar up everything (inc all the deps in the mvn repo)
            # this will include the packaged and 'installed' jar
            tar -czf $$MVN_TARBALL -C $$MVN_LOCAL_REPO_DIR . >/dev/null
        """ % " ".join(DEP_LOCATIONS),
        message = "Building: %s" % native.package_name(),
        visibility = ["//visibility:public"],
    )
