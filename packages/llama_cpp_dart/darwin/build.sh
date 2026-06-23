#!/bin/bash
# SIGN_IDENTITY="Apple Development: netdur@gmail.com (YJ252A5FQ8)" bash darwin/create_xcframework.sh

# Exit on error
set -e

# Get the directory where the script is located
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to handle errors
handle_error() {
    echo "Error: Build process failed."
    exit 1
}

# Set up trap to catch errors
trap handle_error ERR

# Function to build and fix rpaths for a platform
build_platform() {
    local platform=$1
    
    echo "Building for ${platform}..."
    bash "${script_dir}/run_build.sh" src/llama.cpp YW2A442B88 ${platform}
    if [ $? -ne 0 ]; then
        echo "Error: ${platform} build failed."
        exit 1
    fi
    
    cd "${script_dir}"
    echo "Fixing rpaths for ${platform}..."
    bash "fix_rpath.sh" ${platform}
    if [ $? -ne 0 ]; then
        echo "Error: Fixing rpaths for ${platform} failed."
        exit 1
    fi
    cd "${script_dir}/.."
}

# Uncomment the platforms you want to build
build_platform "MAC_ARM64"
# build_platform "OS64"
# build_platform "SIMULATOR64"
# build_platform "SIMULATORARM64"

echo "Build completed successfully for all platforms."