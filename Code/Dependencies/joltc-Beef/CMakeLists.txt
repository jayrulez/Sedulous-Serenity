cmake_minimum_required(VERSION 3.16)

# Enable new MSVC runtime library handling
cmake_policy(SET CMP0091 NEW)

# Set static runtime library for both Debug (/MTd) and Release (/MT)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>" CACHE STRING "MSVC Runtime Library" FORCE)

# Force JPH_MASTER_PROJECT=ON so that the static runtime library setting is applied
set(JPH_MASTER_PROJECT ON CACHE BOOL "Build as master project" FORCE)

# Build static library, disable samples and install
set(JPH_BUILD_SHARED OFF CACHE BOOL "Build shared library" FORCE)
set(JPH_SAMPLES OFF CACHE BOOL "Build samples" FORCE)
set(JPH_INSTALL OFF CACHE BOOL "Install target" FORCE)

add_subdirectory(joltc)