cmake_minimum_required(VERSION 3.14)
project(alist_to_hf_migrator LANGUAGES CXX)

set(BINARY_NAME "alist_to_hf_migrator")

cmake_policy(SET CMP0091 NEW)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_INSTALL_RPATH "${CMAKE_INSTALL_PREFIX}/bin")

add_subdirectory("runner")

add_custom_target(install_bundle ALL
  COMMAND ${CMAKE_COMMAND} -E copy_directory
    "${PROJECT_SOURCE_DIR}/flutter"
    "${CMAKE_BINARY_DIR}/flutter"
)
