{
    Windows:: {
        downloads+: {
            MSYS2: {name: "msys2", version: "20190524", platformspecific: true},
            DEVKIT: {name: "devkit", version: "VS2017-15.5.5", platformspecific: true},
        },
        capabilities+: ["windows"],
        name+: "-windows",
        environment+: {
            CI_OS: "windows",
            PATH: "$MSYS2\\usr\\bin;$PATH",
            # Don't fake ln by copying files
            MSYS: "winsymlinks:nativestrict",
            # Prevent expansion of `/` in args
            MSYS2_ARG_CONV_EXCL: "-Fe;/Gy"
        },
        setup+: [
            # Initialize MSYS2
            ["bash", "--login"],
        ],
    },
    Linux:: {
        docker: {
          "image": "phx.ocir.io/oraclelabs2/c_graal/jdk-snapshot-builder:2018-11-19"
        },
        capabilities+: ["linux"],
        name+: "-linux",
        environment+: {
            CI_OS: "linux"
        },
    },
    Darwin:: {
        packages+: {
            # No need to specify a "make" package as Mac OS X has make 3.81
            # available once Xcode has been installed.
        },
        environment+: {
            CI_OS: "darwin",
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
        capabilities+: ["darwin_sierra"],
        name+: "-darwin",
    },

    AMD64:: {
        capabilities+: ["amd64"],
        name+: "-amd64",
        environment+: {
            CI_ARCH: "amd64"
        }
    },

    AArch64:: {
        capabilities+: ["aarch64"],
        name+: "-aarch64",
        environment+: {
            CI_ARCH: "aarch64"
        }
    },

    Eclipse:: {
        downloads+: {
            ECLIPSE: {
                name: "eclipse",
                version: "4.5.2",
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
                version: "4.5.1",
                platformspecific: false
            }
        }
    },

    OracleJDK:: {
        name+: "-oraclejdk",
        downloads+: {
            JAVA_HOME: {
                name : "oraclejdk",
                version : "11.0.3+12",
                platformspecific: true
            }
        }
    },

    Build:: {
        environment: {
            MAKE : "make",
        },
        packages+: {
            # GR-19828
            "00:pip:logilab-common ": "==1.4.4",
            "01:pip:astroid" : "==1.1.0",
            "pip:pylint" : "==1.1.0",
        },
        name: "gate",
        timelimit: "1:00:00",
        diskspace_required: "10G",
        logs: ["*.log"],
        targets: ["gate"],
        run+: [
            # Make release build
            ["sh", "configure", "--with-debug-level=release",
                          "--with-jvm-features=graal",
                          "--with-native-debug-symbols=none",
                          "--with-jvm-variants=server",
                          "--disable-warnings-as-errors",
                          "--with-boot-jdk=${JAVA_HOME}",
                          "--with-devkit=${DEVKIT}"],
            ["$MAKE", "CONF=release", "images"],

            # Make fastdebug build
            ["sh", "configure", "--with-debug-level=fastdebug",
                          "--with-jvm-features=graal",
                          "--with-native-debug-symbols=external",
                          "--with-jvm-variants=server",
                          "--disable-warnings-as-errors",
                          "--with-boot-jdk=${JAVA_HOME}",
                          "--with-devkit=${DEVKIT}"],
            ["$MAKE", "CONF=fastdebug", "images"],
        ],
    },

    builds: [
        self.Build + mach
        for mach in [
            self.Linux + self.AMD64 + self.OracleJDK,
            self.Linux + self.AArch64 + self.OracleJDK,
            self.Darwin + self.AMD64 + self.OracleJDK,
            self.Windows + self.AMD64 + self.OracleJDK,
        ]
    ] + [
        self.Build + {
            name: "gate-staticjdklibs",
            run: [
                # Make static-jdk-libs build
                ["sh", "configure", "--with-debug-level=release",
                              "--disable-warnings-as-errors",
                              "--with-native-debug-symbols=none",
                              "--with-boot-jdk=${JAVA_HOME}",
                              "--with-devkit=${DEVKIT}"],
                ["$MAKE", "CONF=release", "static-libs-image"],
                ["python", "-u", "ci_test.py", "release"],

                # Make static-jdk-libs build (fastdebug)
                ["sh", "configure", "--with-debug-level=fastdebug",
                              "--disable-warnings-as-errors",
                              "--with-native-debug-symbols=external",
                              "--with-boot-jdk=${JAVA_HOME}",
                              "--with-devkit=${DEVKIT}"],
                ["$MAKE", "CONF=fastdebug", "static-libs-image"],
                ["python", "-u", "ci_test.py", "fastdebug"],
            ]
        } + mach
        for mach in [
            self.Linux + self.AMD64 + self.OracleJDK,
            self.Darwin + self.AMD64 + self.OracleJDK,
            self.Windows + self.AMD64 + self.OracleJDK,
        ]
    ]
}
