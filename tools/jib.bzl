def jib(name, base, pom="pom.xml", srcs=[], deps=[], visibility = None):

    PACKAGE_NAME = native.package_name().replace("/","_")
    DEP_LOCATIONS = ["$(locations %s)" % d for d in deps] + ["$(locations @src_maven_tree//:%s_deps)" % PACKAGE_NAME]

    native.filegroup(
        name = "jib_srcs",
        srcs = srcs,
    )

    native.genrule(
        name = name,
        srcs = [
            pom,
            ":jib_srcs",
            "@src_maven_tree//:%s_deps" % PACKAGE_NAME
        ] + deps,
        outs = ["%s.tar" % name, "%s.tar.sha256" % name ],
        tools = [ base ],
        toolchains = ["@bazel_tools//tools/jdk:current_java_runtime"],
        local = True,
        cmd = """
            # Set the java for repeatability - see toolchains
            export JAVA_HOME=$$PWD/$(JAVABASE)

            TAR_OUT=$$PWD/$(location %s.tar)
            BASE_IMAGE_TAR=$$PWD/$(location %s).tar
            BUILD_ROOT=$$PWD
            PROJECT_DIR=$$PWD/$$(dirname $(location :pom.xml))

            # Change into the directory with the main pom
            # And run JIB
            cd $$PROJECT_DIR
            mvn -B -q -N compile com.google.cloud.tools:jib-maven-plugin:3.3.1:buildTar -Djib.from.image=tar://$$BASE_IMAGE_TAR -Djib.outputPaths.tar=$$TAR_OUT -Djib.outputPaths.digest=$$TAR_OUT.sha256
            sed -i'.orig' 's/sha256\\://' $$TAR_OUT.sha256
        """ % (name, base),
        message = "Building: %s" % native.package_name(),
        visibility = ["//visibility:public"],
    )

    native.alias(
        name = "jib",
        actual = ":%s" % name,
    )