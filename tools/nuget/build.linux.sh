#!/bin/bash

# Automatically exit on error
set -e


# =================================================== #
# STEP 1: Setup all variables needed during the build #
# =================================================== #

if [[ -z "$1" ]]; then
    echo "Usage: $0 <RID> [<cxx_compiler> <c_compiler>]"
    echo "Example: $0 linux-arm arm-linux-gnueabihf-g++ arm-linux-gnueabihf-gcc"
    exit 1
fi

echo "Please note that all SFML dependencies must be installed and available to cmake. SFML does not ship with its linux dependencies."

RID="$1"
CXX_COMPILER="$2"
C_COMPILER="$3"

if [[ -n "$CXX_COMPILER" || -n "$C_COMPILER" ]]; then
    if [[ -z "$CXX_COMPILER" || -z "$C_COMPILER" ]]; then
        echo "When overriding compilers, specify both C++ and C compilers."
        exit 1
    fi
fi

CMAKE_COMPILER_ARGS=()
if [[ -n "$CXX_COMPILER" ]]; then
    CMAKE_COMPILER_ARGS+=("-DCMAKE_CXX_COMPILER=$CXX_COMPILER" "-DCMAKE_C_COMPILER=$C_COMPILER")
    echo "Using custom compilers: CXX=$CXX_COMPILER, CC=$C_COMPILER"
fi

SFMLBranch="3.1.0" # The branch or tag of the SFML repository to be cloned
CSFMLDir="$(realpath ../../)"  # The directory of the source code of CSFML

OutDir="./CSFML/runtimes/$RID/native" # The base directory of all CSFML modules, used to copy the final libraries
mkdir -p "$OutDir"
OutDir="$(realpath "$OutDir")"

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

SFMLDir="$(realpath SFML)"

# ================== #
# STEP 3: Build SFML #
# ================== #

rm -rf "$RID"
mkdir -p "$RID"
pushd "$RID"

echo "Building SFML"
mkdir -p SFML
pushd SFML

SFMLBuiltDir="$(realpath .)" # The directory where SFML was built to. Used later to direct cmake when building CSFML

mkdir -p lib
# The directory that contains the final SFML libraries
SFMLLibDir="$(realpath lib)"

cmake -E env LDFLAGS="-z origin" \
    cmake "${CMAKE_COMPILER_ARGS[@]}" \
    '-DCMAKE_POSITION_INDEPENDENT_CODE=ON' \
    '-DBUILD_SHARED_LIBS=OFF' \
    '-DCMAKE_BUILD_TYPE=Release' \
    "-DCMAKE_INSTALL_PREFIX=$SFMLLibDir" \
    "-DCMAKE_LIBRARY_OUTPUT_DIRECTORY=$SFMLLibDir" \
    '-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON' \
    '-DCMAKE_INSTALL_RPATH=$ORIGIN' \
    '-DSFML_USE_SYSTEM_DEPS=OFF' \
    '-DSFML_BUILD_NETWORK=OFF' \
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

# Shared lib
cmake -E env LDFLAGS="-z origin" \
    cmake "${CMAKE_COMPILER_ARGS[@]}" \
    "-DSFML_ROOT=$SFMLLibDir" \
    '-DBUILD_SHARED_LIBS=ON' \
    '-DCSFML_LINK_SFML_STATICALLY=ON' \
    '-DCMAKE_BUILD_TYPE=Release' \
    "-DCMAKE_LIBRARY_OUTPUT_DIRECTORY=$CSFMLLibDir" \
    '-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON' \
    '-DCMAKE_INSTALL_RPATH=$ORIGIN' \
    '-DCSFML_BUILD_NETWORK=OFF' \
    "$CSFMLDir"
cmake --build . --config Release

# Static lib
cmake -E env LDFLAGS="-z origin" \
    cmake "${CMAKE_COMPILER_ARGS[@]}" \
    "-DSFML_ROOT=$SFMLLibDir" \
    '-DBUILD_SHARED_LIBS=OFF' \
    '-DCSFML_LINK_SFML_STATICALLY=ON' \
    '-DCMAKE_BUILD_TYPE=Release' \
    "-DCMAKE_LIBRARY_OUTPUT_DIRECTORY=$CSFMLLibDir" \
    "-DCMAKE_ARCHIVE_OUTPUT_DIRECTORY=$CSFMLLibDir" \
    '-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON' \
    '-DCMAKE_INSTALL_RPATH=$ORIGIN' \
    '-DCSFML_BUILD_NETWORK=OFF' \
    "$CSFMLDir"
cmake --build . --config Release

# ======================================== #
# STEP 5: Copy result to the NuGet folders #
# ======================================== #

copymodule()
{
    MODULE="$1"

    mkdir -p "$OutDir"

    cp "$CSFMLLibDir/libcsfml-$MODULE.so" "$OutDir"
    cp "$CSFMLLibDir"/libcsfml-$MODULE*.a "$OutDir"
}

copymodule audio
copymodule graphics
copymodule system
copymodule window

popd # Pop CSFML
popd # Pop $RID
popd # Pop Build