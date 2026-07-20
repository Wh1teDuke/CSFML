#!/bin/bash

# Automatically exit on error
set -e
set -x

# =================================================== #
# STEP 1: Setup all variables needed during the build #
# =================================================== #

if [[ -z "$1" ]]; then
    echo "Please specify the platform Runtime Identifier as an argument to this script"
    exit 1
fi

echo "Please note that all SFML dependencies must be installed and available to cmake. SFML does not ship with its linux dependencies."

RID="$1"

SFMLBranch="3.1.0" # The branch or tag of the SFML repository to be cloned
CSFMLDir="$(grealpath "$(git rev-parse --show-toplevel)")" # The directory of the source code of CSFML

OutDir="./CSFML/runtimes/$RID/native" # The base directory of all CSFML modules, used to copy the final libraries
mkdir -p "$OutDir"
OutDir="$(grealpath "$OutDir")"

echo "Building $RID"

mkdir -p "Build"
pushd "Build"

# ================== #
# STEP 2: Clone SFML #
# ================== #

if [[ ! -d "SFML/.git" ]]; then
    echo "Cloning SFML"
    rm -rf "SFML"
    git clone --branch "$SFMLBranch" --depth 1 "https://github.com/SFML/SFML.git" "SFML"
fi

SFMLDir="$(grealpath SFML)"

# ================== #
# STEP 3: Build SFML #
# ================== #

rm -rf "$RID"
mkdir -p "$RID"
pushd "$RID"

echo "Building SFML"
mkdir -p SFML
pushd SFML

SFMLBuiltDir="$(grealpath .)" # The directory where SFML was built to. Used later to direct cmake when building CSFML

mkdir -p lib
# The directory that contains the final SFML libraries
SFMLLibDir="$(grealpath lib)"

if [ $RID == "osx-x64" ]; then
    ARCHITECTURE="x86_64"
elif [ $RID == "osx-arm64" ]; then
    ARCHITECTURE="arm64"

    echo "Note: arm64 is only supported starting with SFML 2.6"
else
    echo "Unsupported RID provided. Use 'osx-x64', 'osx-arm64'"
    exit 1
fi

cmake -E env \
    cmake -G "Unix Makefiles" \
          -D 'CMAKE_POSITION_INDEPENDENT_CODE=ON' \
          -D 'BUILD_SHARED_LIBS=OFF' \
          -D 'SFML_BUILD_FRAMEWORKS=OFF' \
          -D 'CMAKE_BUILD_TYPE=Release' \
          -D "CMAKE_OSX_ARCHITECTURES=$ARCHITECTURE" \
          -D "CMAKE_LIBRARY_OUTPUT_DIRECTORY=$SFMLLibDir" \
          -D 'CMAKE_BUILD_WITH_INSTALL_RPATH=ON' \
          -D 'CMAKE_INSTALL_RPATH=@loader_path' \
          -D "CMAKE_INSTALL_PREFIX=$SFMLLibDir" \
          -D "SFML_DEPENDENCIES_INSTALL_PREFIX=$SFMLLibDir" \
          -D "SFML_MISC_INSTALL_PREFIX=$SFMLLibDir" \
          -D "SFML_BUILD_NETWORK=0" \
          "$SFMLDir"

cmake --build . --config Release --target install

popd # Pop SFML

# =================== #
# STEP 4: Build CSFML #
# =================== #

echo "Building CSFML using SFML at $SFMLBuiltDir"
mkdir -p CSFML
pushd CSFML

mkdir -p lib
CSFMLLibDir="$(realpath lib)" # The directory that contains the final CSFML libraries. Used to copy the result into SFML.Net

cmake -E env \
    cmake -G "Unix Makefiles" \
          -D "SFML_ROOT=$SFMLLibDir" \
          -D 'BUILD_SHARED_LIBS=ON' \
          -D 'CSFML_LINK_SFML_STATICALLY=ON' \
          -D 'CMAKE_BUILD_TYPE=Release' \
          -D "CMAKE_OSX_ARCHITECTURES=$ARCHITECTURE" \
          -D "CMAKE_LIBRARY_OUTPUT_DIRECTORY=$CSFMLLibDir" \
          -D 'CMAKE_BUILD_WITH_INSTALL_RPATH=ON' \
          -D 'CMAKE_INSTALL_RPATH=@loader_path' \
          -D "CMAKE_INSTALL_PREFIX=$CSFMLLibDir" \
          -D "INSTALL_MISC_DIR=$CSFMLLibDir" \
          -D "CSFML_BUILD_NETWORK=0" \
          "$CSFMLDir"
cmake --build . --config Release --target install

# ======================================== #
# STEP 5: Copy result to the NuGet folders #
# ======================================== #

CSFMLMajorMinor="3.1"
CSFMLMajorMinorPatch="$CSFMLMajorMinor.0"

# Copies one SFML and CSFML module into the NuGet package
# The module name must be passed to this function as an argument, in lowercase
# This function then copies $CSFMLLibDir/libcsfml-(module).so into $OutDir
copymodule()
{
    MODULE="$1"

    mkdir -p "$OutDir"

    # SFML.Net only searches for the name with common pre- and suffixes
    # As such we need to ship e.g. libcsfml-graphics.dylib
    cp "$CSFMLLibDir/libcsfml-$MODULE.dylib" "$OutDir"
    cp "$CSFMLLibDir/libcsfml-$MODULE.$CSFMLMajorMinor.dylib" "$OutDir"
}

copymodule audio
copymodule graphics
copymodule system
copymodule window

popd # Pop CSFML
popd # Pop $RID
popd # Pop Build
