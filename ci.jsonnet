{
    Windows:: {
        capabilities+: ["windows"],
        name+: "-windows",
        environment+: {
            PATH : "$MKS_HOME;$PATH",  # Makes the `test` utility available
            CI_OS: "windows"
        },
        packages+: {
            msvc: "==10.0",
        },
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
    Solaris:: {
        downloads+: {
          AUTOCONF_DIR: {name: "autoconf", version: "2.69-AUTOCONF_DIR-relative", platformspecific: true}
        },
        packages+: {
            git: ">=1.8.3",
            make : ">=3.83",
            solarisstudio: "==12.6"
        },
        capabilities+: ["solaris"],
        name+: "-solaris",
        environment+: {
            MAKE : "gmake",
            # Limit jobs to mitigate problem described in GR-3554
            JOBS : "4",
            CI_OS : "solaris",
            PATH : "${AUTOCONF_DIR}/bin:${PATH}"
        },
        setup+: [
            # Autoconf stores the install prefix on various places, this command rewrites the paths with $AUTOCONF_DIR.
            # It assumes that the install prefix of autoconf is /opt/autoconf-2.69.
            ["perl", "-pi.bak", "-e", "s:/opt/autoconf-2.69:${AUTOCONF_DIR}:", "$AUTOCONF_DIR/share/autoconf/autom4te.cfg"]
        ]
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
    SPARCv9:: {
        capabilities+: ["sparcv9"],
        name+: "-sparcv9",
        timelimit: "1:30:00",
        environment+: {
            CI_ARCH: "sparcv9"
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
                version : "11.0.3+7",
                platformspecific: true
            }
        }
    },

    Build:: {
        environment: {
            MAKE : "make",
        },
        packages+: {
            "pip:astroid" : "==1.1.0",
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
                          "--with-native-debug-symbols=external",
                          "--with-jvm-variants=server",
                          "--disable-warnings-as-errors",
                          "--with-zlib=bundled", #JDK-8175795
                          "--with-boot-jdk=${JAVA_HOME}"],
            ["$MAKE", "CONF=release", "images"],

            # Make fastdebug build
            ["sh", "configure", "--with-debug-level=fastdebug",
                          "--with-jvm-features=graal",
                          "--with-native-debug-symbols=external",
                          "--with-jvm-variants=server",
                          "--disable-warnings-as-errors",
                          "--with-zlib=bundled", #JDK-8175795
                          "--with-boot-jdk=${JAVA_HOME}"],
            ["$MAKE", "CONF=fastdebug", "images"],
        ],
    },

    builds: [
        self.Build + mach
        for mach in [
            self.Linux + self.AMD64 + self.OracleJDK,
            self.Darwin + self.AMD64 + self.OracleJDK,
            self.Windows + self.AMD64 + self.OracleJDK,
            self.Solaris + self.SPARCv9 + self.OracleJDK,
        ]
    ]
}
