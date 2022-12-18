def mvn(name, pom="pom.xml", srcs=[], deps=[], visibility = None):

    PACKAGE_NAME = native.package_name().replace("/","_")
    DEP_LOCATIONS = ["$(locations %s)" % d for d in deps] + ["$(locations @src_maven_tree//:%s_deps)" % PACKAGE_NAME]

    native.filegroup(
        name = "mvn_srcs",
        srcs = srcs,
    )

    native.genrule(
        name = name,
        srcs = [
            pom,
            ":mvn_srcs",
            "@src_maven_tree//:%s_deps" % PACKAGE_NAME
        ] + deps,
        outs = ["%s.tar" % name],
        toolchains = ["@bazel_tools//tools/jdk:current_java_runtime"],
        local = True,
        cmd = """
            # Set the java for repeatability - see toolchains
            export JAVA_HOME=$$PWD/$(JAVABASE)

            BUILD_ROOT=$$PWD
            MVN_TARGET_TARBALL=$$BUILD_ROOT/$@
            PROJECT_DIR=$$PWD/$$(dirname $(location :pom.xml))
            TARGET_DIR=$$(dirname $(location :pom.xml))/target
            mkdir -p $$TARGET_DIR

            # Change into the directory with the main pom
            cd $$PROJECT_DIR

            # Maven install to the local maven repo
            # Skip tests and skip compiling tests
            # Batch mode, quiet mode, non-recursive mode
            mvn -B -q -N install -Dmaven.test.skip=true -DskipTests

            tar -czf $$MVN_TARGET_TARBALL -C $$BUILD_ROOT $$TARGET_DIR >/dev/null
        """,
        message = "Building: %s" % native.package_name(),
        visibility = ["//visibility:public"],
    )

    native.alias(
        name = "mvn",
        actual = ":%s" % name,
    )