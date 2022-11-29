# rules_simple_bundle

Add to `WORKSPACE`:
```bash
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")

git_repository(
    name = "rules_simple_bundle",
    remote = "https://github.com/robertgates55/rules_simple_bundle.git",
    branch = "main"
)
load(
    "@rules_simple_bundle//:defs.bzl",
    "bundle_fetch",
)
bundle_fetch(
    name = "src_webapp_bundle",
    # If your Gemfile references local gems:
    srcs = [
        "//src/webapp:engines/cube_api/Gemfile",
        "//src/webapp:engines/cube_api/cube_api.gemspec",
        "//src/webapp:engines/cube_api/lib/cube_api/version.rb",
        "//src/webapp:engines/ui/Gemfile",
        "//src/webapp:engines/ui/lib/ui/version.rb",
        "//src/webapp:engines/ui/ui.gemspec",
    ],
    gemfile = "//src/webapp:Gemfile",
    gemfile_lock = "//src/webapp:Gemfile.lock",
)
```


Then in your `BUILD` rules you can use the downloaded/installed gem bundles in various ways.

All are `.tar`s that you can use wherever you can use `pkg_tar` outputs.

Single gems: (`<GEM>>-gem-install`)
```azure
...
      "@src_webapp_bundle//:nokogiri-gem-install,
...
```

Groups: (`gems-<GROUP>`)
```azure
...
      "@src_webapp_bundle//:gems-default",
      "@src_webapp_bundle//:gems-production",
      "@src_webapp_bundle//:gems-assets",
...
```

All: (`gems`)
```azure
...
      "@src_webapp_bundle//:gems",
...
```