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
    ] + [ self.Mach5Build + self.Linux + self.AMD64 + self.OracleJDK ],

    Mach5Build:: {
        name: "gate-labsjdk11-mach5",
        targets: ["gate"],
        environment : {
            CI_CACHE : "${SLAVE_LOCAL_CACHE}/labsjdk11-builder/"
        },
        logs : [
            "*.log",
            "*.txt"
        ],
        setup : [
            ["set-export", "CI_DATE", ["date"]]
        ],
        timelimit: "1:00:00",
        run+: [
            ["curl", "-g", "--output", "mach5-distribution.zip",
             "https://java.se.oracle.com/artifactory/jpg-infra-local/com/oracle/java/sparky/mach5/[RELEASE]/mach5-[RELEASE]-distribution.zip"],
            ["unzip", "mach5-distribution.zip"],
            ["mv", "mach5-*-distribution", "mach5"],
            ["mach5/bin/mach5", "version"],

            # Create or refresh local cache of jdk11u tree
            ["python", "-u", "clone_jdk_repos.py", "jdk11u", "${CI_CACHE}", "ssh://git@ol-bitbucket.us.oracle.com:7999/g/labsjdk-11.git", "master",
             "http://closedjdk.us.oracle.com/jdk-updates/jdk11u", "tip"],

            ["ls", "-l"],

            ["mach5/bin/mach5", "remote-build-and-test",
             "--src-root", "jdk11u",
             "--email", "tom.rodriguez@oracle.com",
             "--id-tag", "graal-integration",
             "--log-level", "INFO",
             "--job", "builds-tier1,hs-tier1,hs-tier3-graal,hs-tier4-graal",
             "--comment", "labjdk11 gate test"]
        ]
    },
}
