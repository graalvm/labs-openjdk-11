local defs = import "defs.jsonnet";

# https://github.com/graalvm/labs-openjdk-11/blob/master/doc/testing.md
local run_test_spec = "test/hotspot/jtreg/compiler/jvmci";

local labsjdk_builder_version = "66c43e01a537017021f186f9063796e2f82cd2aa";
local os(conf) = conf.environment.CI_OS;

{
    overlay: "436e17726b16bb1af9552c0f096d1bfbe7abccd8",
    specVersion: "2",

    OSBase:: {
        path(unixpath):: unixpath,
        exe(unixpath):: unixpath,
        jdk_home(java_home):: self.path(java_home),
        java_home(jdk_home):: self.path(jdk_home),
        copydir(src, dst):: ["cp", "-r", src, dst],
        environment+: {
            JIB_PATH: "${PATH}",
            MAKE : "make",
            ZLIB_BUNDLING: "system",
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
        packages : {
            "devkit:VS2017-15.5.5+1" : "==0"
        },
        capabilities+: ["windows"],
        name+: "-windows-cygwin",
        environment+: {
            CI_OS: "windows",
            JIB_OS: "windows",
            JIB_PLATFORM_OS: "windows",
            JIB_PATH: "$CYGWIN\\bin;$PATH",
            ZLIB_BUNDLING: "bundled"
        },
    },
    Linux:: self.OSBase + {
        capabilities+: ["linux"],
        name+: "-linux",
        environment+: {
            CI_OS: "linux",
            JIB_OS: "linux",
            JIB_PLATFORM_OS: "linux",
        },
    },
    LinuxDocker:: self.Linux {
        docker: {
          "image": defs.linux_docker_image
        },
    },
    LinuxDevkit:: self.Linux {
        packages : {
            "devkit:gcc7.3.0-OEL6.4+1" : "==1"
        },
    },
    LinuxMuslDocker:: self.Linux {
        "docker": {
            "image": "phx.ocir.io/oraclelabs2/c_graal/jdk-musl-snapshot-builder"
        },
    },
    Darwin:: self.OSBase + {
        jdk_home(java_home):: java_home + "/../..",
        java_home(jdk_home):: jdk_home + "/Contents/Home",
        packages+: {
            # No need to specify a "make" package as Mac OS X has make 3.81
            # available once Xcode has been installed.
        },
        environment+: {
            CI_OS: "darwin",
            JIB_OS: "macosx",
            JIB_PLATFORM_OS: "osx",
            ac_cv_func_basename_r: "no",
            ac_cv_func_clock_getres: "no",
            ac_cv_func_clock_gettime: "no",
            ac_cv_func_clock_settime: "no",
            ac_cv_func_dirname_r: "no",
            ac_cv_func_getentropy: "no",
            ac_cv_func_mkostemp: "no",
            ac_cv_func_mkostemps: "no",
            MACOSX_DEPLOYMENT_TARGET: "10.11"
        },
        name+: "-darwin",
        capabilities+: ["darwin_mojave_6"] # JIB only works on the darwin_mojave slaves
    },

    AMD64:: {
        capabilities+: ["amd64"],
        name+: "-amd64",
        environment+: {
            CI_ARCH: "amd64",
            JIB_ARCH: "x64"
        }
    },

    AMD64Musl:: self.AMD64 + {
        name+: "-musl",
        environment+: {
            CI_ARCH+: "-musl",
        }
    },

    AArch64:: {
        capabilities+: ["aarch64"],
        name+: "-aarch64",
        environment+: {
            CI_ARCH: "aarch64",
            JIB_ARCH: "aarch64"
        }
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
                name : "oraclejdk",
                version : "11.0.3+12",
                platformspecific: true
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
            ["git", "fetch", "--tags"],
        ] + (if os(conf) == "windows" then [
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

    Build(conf, is_musl_build):: conf + setupJDKSources(conf) + {
        packages+: if is_musl_build == "false" then {
            # GR-19828
            "00:pip:logilab-common ": "==1.4.4",
            "01:pip:astroid" : "==1.1.0",
            "pip:pylint" : "==1.1.0",
        } else {},
        name: "build-jdk" + conf.name,
        timelimit: "1:50:00",
        diskspace_required: "10G",
        logs: ["*.log"],
        targets: ["gate"],

        run+: [
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

            # Make release build
            ["set-export", "JAVA_HOME", conf.path("${PWD}/../release-java-home")],
            ["python3", "-u", conf.path("${LABSJDK_BUILDER_DIR}/build_labsjdk.py"),
                "--boot-jdk=${BOOT_JDK}",
                "--clean-after-build",
                "--jdk-debug-level=release",
                "--test=" + run_test_spec,
                "--java-home-link-target=${JAVA_HOME}",
                "${JDK_SRC_DIR}"
            ],
            [conf.exe("${JAVA_HOME}/bin/java"), "-version"],

            # Make fastdebug build
            ["set-export", "JAVA_HOME_FASTDEBUG", conf.path("${PWD}/../fastdebug-java-home")],
            ["python3", "-u", conf.path("${LABSJDK_BUILDER_DIR}/build_labsjdk.py"),
                "--boot-jdk=${BOOT_JDK}",
                "--clean-after-build",
                "--jdk-debug-level=fastdebug",
                "--test=" + run_test_spec,
                "--java-home-link-target=${JAVA_HOME_FASTDEBUG}",
                "${JDK_SRC_DIR}"
            ],
            [conf.exe("${JAVA_HOME_FASTDEBUG}/bin/java"), "-version"],

            ["set-export", "PATH", "${OLD_PATH}"],

            # Run some basic mx based sanity checks. This is mostly to ensure
            # IDE support does not regress.
            ["mx", "-p", "${JDK_SUITE_DIR}", "checkstyle"],
            ["mx", "-p", "${JDK_SUITE_DIR}", "eclipseinit"],
            ["mx", "-p", "${JDK_SUITE_DIR}", "canonicalizeprojects"],

            # Prepare for publishing
            ["set-export", "JDK_HOME", conf.path("${PWD}/jdk_home")],
            ["cd", "${JAVA_HOME}"],
            conf.copydir(conf.jdk_home("."), "${JDK_HOME}")
        ],

        publishArtifacts+: if is_musl_build == "false" then [
            {
                name: "labsjdk" + conf.name,
                dir: ".",
                patterns: ["jdk_home"]
            }
        ] else [],
    },

    # Downstream Graal branch to test against.
    local downstream_branch = "cpu/graal-vm/20.3", # adapt to signature change in JDK-8233234

    local clone_graal = {
        run+: [
            ["git", "clone", "--quiet", ["mx", "urlrewrite", "https://github.com/graalvm/graal.git"]],
            ["git", "-C", "graal", "checkout", downstream_branch, "||", "true"],
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
            ["${GRAALVM_HOME}/bin/js", "test/nashorn/opt/add.js"],
        ] +
        if os(conf) != "windows" then [
            # Native launchers do not yet support --jvm mode on Windows
            ["${GRAALVM_HOME}/bin/js", "--jvm", "test/nashorn/opt/add.js"]
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

    local build_confs = [
        self.LinuxDevkit + self.AMD64,
        self.Darwin + self.AMD64,
        self.Windows + self.AMD64
    ],

    local graal_confs = [
        self.LinuxDevkit + self.AMD64,
        self.Darwin + self.AMD64,
    ],

    # GR-18864 prevents self.GraalVMTest on AArch64
    local aarch64_confs = [
        self.LinuxDocker + self.AArch64 + self.JTReg + self.BootJDK,
    ],

    local amd64_musl_confs = [
        self.LinuxMuslDocker + self.AMD64Musl + self.MuslBootJDK,
    ],

    builds: [ self.Build(conf, "false") for conf in build_confs ] +
            [ self.CompilerTests(conf) for conf in graal_confs ] +
            [ self.JavaScriptTests(conf) for conf in graal_confs ] +
            [ self.BuildLibGraal(conf) for conf in graal_confs ] +
            [ self.TestLibGraal(conf) for conf in graal_confs ] +

            [ self.Build(conf, "false") for conf in aarch64_confs ] +
            [ self.CompilerTests(conf) for conf in aarch64_confs ] +

            [ self.Build(conf, "true") for conf in amd64_musl_confs ] +

            # GR-20001 prevents reliable Graal testing on Windows
            # but we want to "require" the JDK artifact so that it
            # is uploaded.
            [ self.RunJDK(self.Windows + self.AMD64) ]
}
