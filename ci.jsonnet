# https://github.com/graalvm/labs-openjdk-11/blob/master/doc/testing.md
local run_test_spec = "test/hotspot/jtreg/compiler/jvmci test/jdk/tools/jlink/plugins";

local labsjdk_builder_version = "e9c60b5174490f2012c7c5d60a20aace93209a56";

{
    overlay: "adc52f479f9d2b1f55985066bf95d454702c7a89",
    specVersion: "3",

    mxDependencies:: {
        python_version: "3",
        packages+: {
          "mx": "HEAD",
          "python3": "==3.8.10",
          'pip:pylint': '==2.4.4',
      },
    },

    OSBase:: self.mxDependencies + {
        path(unixpath):: unixpath,
        exe(unixpath):: unixpath,
        jdk_home(java_home):: self.path(java_home),
        java_home(jdk_home):: self.path(jdk_home),
        copydir(src, dst):: ["cp", "-r", src, dst],
        environment+: {
            JIB_PATH: "${PATH}",
            MAKE : "make",
            ZLIB_BUNDLING: "system",
            MX_PYTHON: "python3.8"
        },
    },

    Windows:: self.OSBase + {
        path(unixpath):: std.strReplace(unixpath, "/", "\\"),
        exe(unixpath):: self.path(unixpath) + ".exe",
        # https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/xcopy
        copydir(src, dst):: ["xcopy", self.path(src), self.path(dst), "/e", "/i", "/q"],

        downloads+: {
            CYGWIN: {name: "cygwin", version: "3.0.7", platformspecific: true},
        },
        packages+: {
            # devkit_platform_revisions in make/conf/jib-profiles.js
            "devkit:VS2017-15.5.5+1" : "==0"
        },
        capabilities+: ["windows"],
        name+: "-windows-cygwin",
        os:: "windows",
        environment+: {
            JIB_PATH: "$CYGWIN\\bin;$PATH",
            ZLIB_BUNDLING: "bundled"
        },
    },
    Linux:: self.OSBase + {
        capabilities+: ["linux"],
        name+: "-linux",
        os:: "linux",
    },
    LinuxDockerAMD64(defs):: self.Linux {
        docker: {
            image: defs.linux_docker_image_amd64,
            mount_modules: true
        },
    },
    LinuxDockerAMD64Musl(defs):: self.Linux {
        docker: {
            image: defs.linux_docker_image_amd64_musl
        },
        packages: {},
    },
    LinuxDevkitAMD64:: self.Linux {
        packages+: {
            "devkit:gcc7.3.0-OEL6.4+1" : "==1"
        },
    },
    Darwin:: self.OSBase + {
        jdk_home(java_home):: java_home + "/../..",
        java_home(jdk_home):: jdk_home + "/Contents/Home",
        packages+: {
            # No need to specify a "make" package as Mac OS X has make 3.81
            # available once Xcode has been installed.
        },
        os:: "darwin",
        name+: "-darwin",
    },
    DarwinAMD64:: self.Darwin + self.AMD64 + {
        environment+: {
            ac_cv_func_basename_r: "no",
            ac_cv_func_clock_getres: "no",
            ac_cv_func_clock_gettime: "no",
            ac_cv_func_clock_settime: "no",
            ac_cv_func_dirname_r: "no",
            ac_cv_func_getentropy: "no",
            ac_cv_func_mkostemp: "no",
            ac_cv_func_mkostemps: "no",
            MACOSX_DEPLOYMENT_TARGET: "10.13"
        },
        capabilities+: ["darwin_mojave_6"] # JIB only works on the darwin_mojave slaves
    },
    DarwinAArch64:: self.Darwin + self.AArch64 + {
        capabilities+: ["darwin"],
    },

    AMD64:: {
        capabilities+: ["amd64"],
        name+: "-amd64",
    },

    AMD64Musl:: self.AMD64 + {
        name+: "-musl",
        packages+: {
            "devkit:gcc7.3.0-Alpine3.8+0:musl": "==1"
        }
    },

    AArch64:: {
        capabilities+: ["aarch64"],
        name+: "-aarch64",
    },

    Eclipse:: {
        downloads+: {
            ECLIPSE: {
                name: "eclipse",
                version: "4.14.0",
                platformspecific: true
            }
        },
        environment+: {
            ECLIPSE_EXE: "$ECLIPSE/eclipse"
        },
    },

    JDT:: {
        downloads+: {
            JDT: {
                name: "ecj",
                version: "4.14.0",
                platformspecific: false
            }
        }
    },

    BootJDK:: {
        downloads+: {
            BOOT_JDK: {
                "version": "11.0.16",
                "build_id": "11",
                "name": "jpg-jdk",
                "extrabundles": ["static-libs"],
                "release": true
            }
        }
    },

    MuslBootJDK:: {
        downloads+: {
            BOOT_JDK: {
                name: "labsjdk",
                version: "ce-11.0.7+10-jvmci-20.1-b03-musl-boot",
                platformspecific: true
            }
        },
        environment+: {
            LD_LIBRARY_PATH: "$BOOT_JDK/lib/server"
        }
    },

    JTReg:: {
        downloads+: {
            JT_HOME: {
                name : "jtreg",
                version : "4.2"
            }
        }
    },

    local setupJDKSources(conf) = {
        run+: [
            # To reduce load, the CI system does not fetch all tags so it must
            # be done explicitly as `build_labsjdk.py` relies on it.
            ["git", "fetch", "--quiet", "--tags"],
        ] + (if conf.os == "windows" then [
            # Need to fix line endings on Windows to satisfy cygwin
            # https://stackoverflow.com/a/26408129
            ["set-export", "JDK_SRC_DIR", "${PWD}\\..\\jdk"],
            ["git", "clone", "--quiet", "-c", "core.autocrlf=input", "-c", "gc.auto=0", ".", "${JDK_SRC_DIR}"],
        ] else [
            ["set-export", "JDK_SRC_DIR", "${PWD}"],
        ]) + [
            ["set-export", "JDK_SUITE_DIR", "${JDK_SRC_DIR}"]
        ],
    },

    Build(defs, conf, is_musl_build):: conf + setupJDKSources(conf) + (if is_musl_build then self.MuslBootJDK else self.BootJDK) + {
        name: "build-jdk" + conf.name,
        timelimit: "1:50:00",
        diskspace_required: "10G",
        logs: ["*.log"],
        targets: ["gate"],

        local build_labsjdk(jdk_debug_level, java_home_env_var) = [
            ["set-export", java_home_env_var, conf.path("${PWD}/../%s-java-home" % jdk_debug_level)],
            ["python3", "-u", conf.path("${LABSJDK_BUILDER_DIR}/build_labsjdk.py"),
                "--boot-jdk=${BOOT_JDK}",
                "--clean-after-build",
                "--jdk-debug-level=" + jdk_debug_level,
                "--test=" + run_test_spec,
                "--java-home-link-target=${%s}" % java_home_env_var,
            ] + (if is_musl_build then ['--bundles=static-libs'] else [])
            + [
                "${JDK_SRC_DIR}"
            ]
        ] + (if !is_musl_build then
                [[conf.exe("${%s}/bin/java" % java_home_env_var), "-version"]]
            else
                []),

        run+: (if !is_musl_build then [
            # Run some basic mx based sanity checks. This is mostly to ensure
            # IDE support does not regress.
            ["set-export", "JAVA_HOME", "${BOOT_JDK}"],
            (if std.endsWith(conf.name, 'darwin-aarch64') then ['echo', 'no checkstyle available on darwin-aarch64'] else ["mx", "-p", "${JDK_SUITE_DIR}", "checkstyle"]),
            ["mx", "-p", "${JDK_SUITE_DIR}", "eclipseinit"],
            ["mx", "-p", "${JDK_SUITE_DIR}", "canonicalizeprojects"],
        ] else []) + [
            ["set-export", "LABSJDK_BUILDER_DIR", conf.path("${PWD}/../labsjdk-builder")],
            ["git", "clone", "--quiet", "-c", "core.autocrlf=input", "-c", "gc.auto=0", defs.labsjdk_builder_url, "${LABSJDK_BUILDER_DIR}"],
            ["git", "-C", "${LABSJDK_BUILDER_DIR}", "checkout", labsjdk_builder_version],

            # This restricts cygwin to be on the PATH only while using jib.
            # It must not be on the PATH when building Graal.
            ["set-export", "OLD_PATH", "${PATH}"],
            ["set-export", "PATH", "${JIB_PATH}"],
            ["set-export", "JIB_DATA_DIR", conf.path("${PWD}/../jib")],
            ["set-export", "JIB_SERVER", defs.jib_server],
            ["set-export", "JIB_SERVER_MIRRORS", defs.jib_server_mirrors],
        ] +
        build_labsjdk("release", "JAVA_HOME") +
        build_labsjdk("fastdebug", "JAVA_HOME_FASTDEBUG") +
        [
            ["set-export", "PATH", "${OLD_PATH}"],

            # Prepare for publishing
            ["set-export", "JDK_HOME", conf.path("${PWD}/jdk_home")],
            ["cd", "${JAVA_HOME}"],
            conf.copydir(conf.jdk_home("."), "${JDK_HOME}")
        ],

        publishArtifacts+: if !is_musl_build then [
            {
                name: "labsjdk" + conf.name,
                dir: ".",
                patterns: ["jdk_home"]
            }
        ] else [
            # In contrast to the labsjdk-builder repo, the gate in this repo
            # does not bundle the musl static library into the main JDK. That is
            # why the musl static library builder does not publish anything.
            # The musl-based builder in this repo exists solely to ensure
            # the musl build does not regress.
        ],
    },

    # Downstream Graal branch to test against.
    local downstream_branch = "me/GR-42125_downstream",

    local clone_graal = {
        run+: [
            ["git", "clone", "--quiet", ["mx", "urlrewrite", "https://github.com/graalvm/graal.git"]],
            # Use branch recorded by previous builder or record it now for subsequent builder(s)
            ["test", "-f", "graal.commit", "||", "echo", downstream_branch, ">graal.commit"],
            ["git", "-C", "graal", "checkout", ["cat", "graal.commit"], "||", "true"],
            ["git", "-C", "graal", "rev-list", "-n", "1", "HEAD", ">graal.commit"],
        ]
    },

    local requireLabsJDK(conf) = {
        requireArtifacts+: [
            {
                name: "labsjdk" + conf.name,
                dir: "."
            }
        ],
        run+: [
            ["set-export", "JAVA_HOME", conf.java_home("${PWD}/jdk_home")]
        ]
    },

    CompilerTests(conf):: conf + clone_graal + requireLabsJDK(conf) + {
        name: "test-compiler" + conf.name,
        timelimit: "1:00:00",
        logs: ["*.log"],
        targets: ["gate"],
        run+: [
            ["mx", "-p", "graal/compiler", "gate", "--tags", "build,test,bootstraplite"]
        ]
    },

    # Build and test JavaScript on GraalVM
    JavaScriptTests(conf):: conf + clone_graal + requireLabsJDK(conf) + {
        local jsvm = ["mx", "-p", "graal/vm",
            "--dynamicimports", "/graal-js,/substratevm",
            "--components=Graal.js,Native Image",
            "--native-images=js"],

        name: "test-js" + conf.name,
        timelimit: "1:00:00",
        logs: ["*.log"],
        targets: ["gate"],
        run+: [
            # Build and test JavaScript on GraalVM
            jsvm + ["build"],
            ["set-export", "GRAALVM_HOME", jsvm + ["graalvm-home"]],
            ["${GRAALVM_HOME}/bin/js", "js/graal-js/test/smoketest/primes.js"],
        ] +
        if conf.os != "windows" then [
            # Native launchers do not yet support --jvm mode on Windows
            ["${GRAALVM_HOME}/bin/js", "--jvm", "js/graal-js/test/smoketest/primes.js"]
            ] else []
    },

    # Build LibGraal
    BuildLibGraal(conf):: conf + clone_graal + requireLabsJDK(conf) + {
        name: "build-libgraal" + conf.name,
        timelimit: "1:00:00",
        logs: ["*.log"],
        targets: ["gate"],
        publishArtifacts: [
            {
                name: "libgraal" + conf.name + ".graal.commit",
                dir: ".",
                patterns: ["graal.commit"]
            },
            {
                name: "libgraal" + conf.name,
                dir: ".",
                patterns: ["graal/*/mxbuild"]
            }
        ],
        run+: [
            ["mx", "-p", "graal/vm", "--env", "libgraal",
                "--extra-image-builder-argument=-J-esa",
                "--extra-image-builder-argument=-H:+ReportExceptionStackTraces", "build"],
        ]
    },

    local requireLibGraal(conf) = {
        requireArtifacts+: [
            {
                name: "libgraal" + conf.name + ".graal.commit",
                dir: ".",
                autoExtract: true
            },
            {
                name: "libgraal" + conf.name,
                dir: ".",
                autoExtract: false
            }
        ],
    },

    # Test LibGraal
    TestLibGraal(conf):: conf + clone_graal + requireLabsJDK(conf) + requireLibGraal(conf) {
        name: "test-libgraal" + conf.name,
        timelimit: "1:00:00",
        logs: ["*.log"],
        targets: ["gate"],
        run+: [
            ["unpack-artifact", "libgraal" + conf.name],
            ["mx", "-p", "graal/vm",
                "--env", "libgraal",
                "gate", "--task", "LibGraal"],
        ]
    },

    # Run LabsJDK
    RunJDK(conf):: conf + requireLabsJDK(conf) {
        name: "run-jdk" + conf.name,
        logs: ["*.log"],
        targets: ["gate"],
        run+: [
            [conf.exe("${JAVA_HOME}/bin/java"), "-version"],
        ]
    },

    local build_confs(defs) = [
        self.LinuxDevkitAMD64 + self.AMD64,
        self.Linux + self.AArch64,
        self.DarwinAMD64,
        self.DarwinAArch64,
        self.Windows + self.AMD64
    ],

    local graal_confs(defs) = [
        self.LinuxDevkitAMD64 + self.AMD64,
        self.Linux + self.AArch64 + self.JTReg + self.BootJDK,
        self.DarwinAMD64,
        self.DarwinAArch64,
    ],

    local amd64_musl_confs(defs) = [
        self.LinuxDockerAMD64Musl(defs) + self.AMD64Musl,
    ],

    DefineBuilds(defs):: [ self.Build(defs, conf, is_musl_build=false) for conf in build_confs(defs) ] +
            [ self.CompilerTests(conf) for conf in graal_confs(defs) ] +
            [ self.JavaScriptTests(conf) for conf in graal_confs(defs) ] +
            [ self.BuildLibGraal(conf) for conf in graal_confs(defs) ] +
            [ self.TestLibGraal(conf) for conf in graal_confs(defs) ] +
            [ self.Build(defs, conf, is_musl_build=true) for conf in amd64_musl_confs(defs) ] +

            # GR-20001 prevents reliable Graal testing on Windows
            # but we want to "require" the JDK artifact so that it
            # is uploaded.
            [ self.RunJDK(self.Windows + self.AMD64) ],

    local defs = {
      labsjdk_builder_url: "<placeholder",
      linux_docker_image_amd64_musl: "<placeholder",
      linux_docker_image_amd64: "<placeholder",
      jib_server: "<placeholder",
      jib_server_mirrors: "<placeholder"
    },

    builds: self.DefineBuilds(defs)
}
