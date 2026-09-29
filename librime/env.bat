@echo off
set "RIME_ROOT=%CD%"
set "BOOST_ROOT=%RIME_ROOT%\deps\boost"
set "ARCH="
set "PLATFORM_TOOLSET="
set "CC=cl"
set "CXX=cl"
set "CMAKE_GENERATOR=Ninja"
if not defined build_dir set "build_dir=build-x64"
set "CMAKE_BUILD_PARALLEL_LEVEL=8"
set common_cmake_flags=-DCMAKE_POLICY_VERSION_MINIMUM=3.10 "-DCMAKE_C_FLAGS=/DWIN32 /D_WINDOWS /W3 /utf-8" "-DCMAKE_CXX_FLAGS=/DWIN32 /D_WINDOWS /W3 /GR /EHsc /utf-8"



