cmake_minimum_required(VERSION 3.20)
project(ryospice C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK4 REQUIRED IMPORTED_TARGET gtk4)
pkg_check_modules(SPICE_GLIB REQUIRED IMPORTED_TARGET spice-client-glib-2.0)
pkg_check_modules(LIBDRM REQUIRED IMPORTED_TARGET libdrm)

add_executable(ryospice
	src/main.c
	src/display.c
	src/input.c
	src/keymap.c
	src/clipboard.c
)

target_link_libraries(ryospice PRIVATE PkgConfig::GTK4 PkgConfig::SPICE_GLIB PkgConfig::LIBDRM)
