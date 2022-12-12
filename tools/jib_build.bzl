def jib_build(name, base, srcs=[], visibility = None):

  native.genrule(
    name = name,
    srcs = srcs,
    outs = [ "%s.tar" % name, "%s.tar.sha256" % name ],
    tools = [ base ],
    local = True,
    cmd = """
      TAR_OUT=$$PWD/$(location %s.tar)
      BASE_IMAGE_TAR=$$PWD/$(location %s).tar
      RULEDIR=$(RULEDIR)
      cd "$${RULEDIR#$(BINDIR)\\/}"
      mvn compile com.google.cloud.tools:jib-maven-plugin:3.3.1:buildTar -Djib.from.image=tar://$$BASE_IMAGE_TAR -Djib.outputPaths.tar=$$TAR_OUT -Djib.outputPaths.digest=$$TAR_OUT.sha256
      sed -i'.orig' 's/sha256\\://' $$TAR_OUT.sha256
    """ % (name, base)
  )