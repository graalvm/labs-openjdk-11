Welcome to LabsJDK CE 11.

The latest release is available at https://github.com/graalvm/labs-openjdk-11/releases/latest

This is a fork of https://github.com/openjdk/jdk11u-dev (which is a read-only
mirror of https://hg.openjdk.java.net/jdk-updates/jdk11u-dev/) that
exists for the purpose of building a base JDK upon which GraalVM CE 11 is built.

It can be built with:
```
python build_labsjdk.py
```
This will produce a labsjdk installation under `build/labsjdks/release` along with 2 archives in the same
directory; one for the JDK itself and a separate one for the debug symbols.

You can verify the labsjdk build with:
```
./build/labsjdks/release/java_home/bin/java -version
```

The original JDK README is [here](README).
Further information on building JDK 11 is [here](doc/building.md).
