#cmake_minimum_required(VERSION 3.15)

#project(joltc)

#add_library(joltc_static STATIC joltc_stub.c)

#set_property(TARGET joltc_static PROPERTY
#    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

#set_source_files_properties(joltc_stub.c PROPERTIES LANGUAGE C)

#set(CMAKE_C_STANDARD 11)
#set(CMAKE_BUILD_TYPE RelWithDebInfo)

#set_target_properties(joltc_static PROPERTIES OUTPUT_NAME joltc)

add_subdirectory(joltc)