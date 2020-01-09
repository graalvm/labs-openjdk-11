# LabsJDK musl build helper

This folder contains a Dockerfile and helper scripts used to build a musl version of the LabsJDK.

### Requirements

- Docker
- A JDK11 compiled using musl to be used as a boot JDK.

### How to use

Run:`./build_musl_dockerzied.sh` with the following arguments:
- URL from which the boot JDK can be downloaded (**mandatory**)
- Any other arguments passed after the first are forwarded to the build_labsjdk.py script

If there were no errors during compilation, the JDK bundles are placed in the `dist` folder.