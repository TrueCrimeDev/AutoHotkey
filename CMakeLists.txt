cmake_minimum_required(VERSION 3.16)
project(AutoHotkey VERSION 2.1.0 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Windows-specific settings
if(WIN32)
    add_definitions(-DWIN32 -D_WINDOWS -DUNICODE -D_UNICODE)
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        add_definitions(-D_WIN64)
        set(OUTPUT_NAME "AutoHotkey64")
    else()
        set(OUTPUT_NAME "AutoHotkey32")
    endif()
endif()

# PCRE Library
set(PCRE_SOURCES
    source/lib_pcre/pcre/pcre16_chartables.c
    source/lib_pcre/pcre/pcre16_compile.c
    source/lib_pcre/pcre/pcre16_config.c
    source/lib_pcre/pcre/pcre16_exec.c
    source/lib_pcre/pcre/pcre16_fullinfo.c
    source/lib_pcre/pcre/pcre16_get.c
    source/lib_pcre/pcre/pcre16_globals.c
    source/lib_pcre/pcre/pcre16_jit_compile.c
    source/lib_pcre/pcre/pcre16_newline.c
    source/lib_pcre/pcre/pcre16_ord2utf16.c
    source/lib_pcre/pcre/pcre16_refcount.c
    source/lib_pcre/pcre/pcre16_string_utils.c
    source/lib_pcre/pcre/pcre16_study.c
    source/lib_pcre/pcre/pcre16_tables.c
    source/lib_pcre/pcre/pcre16_ucd.c
    source/lib_pcre/pcre/pcre16_valid_utf16.c
    source/lib_pcre/pcre/pcre16_version.c
    source/lib_pcre/pcre/pcre16_xclass.c
)

add_library(pcre16 STATIC ${PCRE_SOURCES})
target_include_directories(pcre16 PRIVATE source/lib_pcre/pcre)
target_compile_definitions(pcre16 PRIVATE
    HAVE_CONFIG_H
    PCRE_STATIC
    SUPPORT_UCP
    SUPPORT_UTF
    SUPPORT_JIT
)

# AutoHotkey sources
set(AHK_SOURCES
    source/ahklib.cpp
    source/ahkversion.cpp
    source/application.cpp
    source/AutoHotkey.cpp
    source/MdFunc.cpp
    source/clipboard.cpp
    source/Debugger.cpp
    source/error.cpp
    source/globaldata.cpp
    source/hook.cpp
    source/hotkey.cpp
    source/input_object.cpp
    source/keyboard_mouse.cpp
    source/os_version.cpp
    source/script.cpp
    source/script2.cpp
    source/script_autoit.cpp
    source/script_com.cpp
    source/script_expression.cpp
    source/script_gui.cpp
    source/script_menu.cpp
    source/script_module.cpp
    source/script_object.cpp
    source/script_object_bif.cpp
    source/script_registry.cpp
    source/SimpleHeap.cpp
    source/StringConv.cpp
    source/TextIO.cpp
    source/util.cpp
    source/var.cpp
    source/window.cpp
    source/WinGroup.cpp
    source/lib/CCallback.cpp
    source/lib/DllCall.cpp
    source/lib/drive.cpp
    source/lib/env.cpp
    source/lib/file.cpp
    source/lib/Gui.ListView.cpp
    source/lib/Gui.StatusBar.cpp
    source/lib/Gui.TreeView.cpp
    source/lib/input.cpp
    source/lib/InputBox.cpp
    source/lib/interop.cpp
    source/lib/math.cpp
    source/lib/pixel.cpp
    source/lib/process.cpp
    source/lib/regex.cpp
    source/lib/sound.cpp
    source/lib/string.cpp
    source/lib/vars.cpp
    source/lib/wait.cpp
    source/lib/win.cpp
)

# Resource file for Windows
set(AHK_RESOURCES
    source/resources/AutoHotkey.rc
)

# Option for console build
option(AHK_CONSOLE_BUILD "Build console version (for shell/terminal use)" OFF)

# Create executable
if(AHK_CONSOLE_BUILD)
    # Console build: uses SUBSYSTEM:CONSOLE, enables stdin/stdout/stderr
    set(OUTPUT_NAME "${OUTPUT_NAME}_Console")
    add_executable(${OUTPUT_NAME} ${AHK_SOURCES} ${AHK_RESOURCES})
    target_compile_definitions(${OUTPUT_NAME} PRIVATE AHK_CONSOLE_BUILD)
else()
    # GUI build: uses SUBSYSTEM:WINDOWS (default)
    add_executable(${OUTPUT_NAME} WIN32 ${AHK_SOURCES} ${AHK_RESOURCES})
endif()

target_include_directories(${OUTPUT_NAME} PRIVATE
    source
    source/lib_pcre/pcre
)

target_compile_definitions(${OUTPUT_NAME} PRIVATE
    PCRE_STATIC
)

# Link libraries
target_link_libraries(${OUTPUT_NAME} PRIVATE
    pcre16
    wsock32
    winmm
    version
    comctl32
    psapi
    wininet
    shlwapi
    uxtheme
    dwmapi
    ole32
    oleaut32
    uuid
)

# MSVC-specific settings
if(MSVC)
    target_compile_options(${OUTPUT_NAME} PRIVATE /W3 /MP)
    target_compile_definitions(${OUTPUT_NAME} PRIVATE _CRT_SECURE_NO_WARNINGS)
    # Use static runtime for standalone exe
    set_property(TARGET ${OUTPUT_NAME} PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    set_property(TARGET pcre16 PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

# MinGW settings
if(MINGW)
    target_link_options(${OUTPUT_NAME} PRIVATE -static -static-libgcc -static-libstdc++)
endif()

# Output directory
set_target_properties(${OUTPUT_NAME} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_SOURCE_DIR}/bin_debug"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_SOURCE_DIR}/bin"
)

message(STATUS "Building AutoHotkey with _ScriptGetLines support")
if(AHK_CONSOLE_BUILD)
    message(STATUS "Console build enabled - errors go to stderr, /ErrorStdOut is default")
endif()
message(STATUS "Output: ${CMAKE_SOURCE_DIR}/bin/${OUTPUT_NAME}.exe")
message(STATUS "")
message(STATUS "Build options:")
message(STATUS "  -DAHK_CONSOLE_BUILD=ON  Build console version for shell/terminal use")
