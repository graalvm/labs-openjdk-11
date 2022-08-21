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

You can pass extra options to the `configure` script using `--configure-option` or `--configure-options`. For example:
```
--configure-option=--disable-warnings-as-errors --configure-option=--with-extra-cxxflags=-fcommon --configure-option=--with-extra-cflags=-fcommon
```
or alternatively:
```
--configure-options=my.config
```
where the contents of the file `my.config` are:
```
--disable-warnings-as-errors
--with-extra-cxxflags=-fcommon
--with-extra-cflags=-fcommon
```

You can verify the labsjdk build with:
```
./build/labsjdks/release/java_home/bin/java -version
```

The original JDK README is [here](README).
Further information on building JDK 11 is [here](doc/building.md).
