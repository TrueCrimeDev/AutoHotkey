cmake_minimum_required(VERSION 3.16)
project(AutoHotkey VERSION 2.1.0 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(MSVC)
    enable_language(ASM_MASM)
endif()

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

if(MSVC)
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        list(APPEND AHK_SOURCES
            source/libx64call/x64call.asm
            source/libx64call/x64stub.asm
        )
    else()
        list(APPEND AHK_SOURCES source/x86call.asm)
    endif()
endif()

if(MINGW)
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        # GAS-syntax equivalents of x64call.asm / x64stub.asm for mingw's
        # assembler. They mirror the MASM versions but omit the unwind
        # directives (no SEH unwind info for these stubs in mingw builds).
        enable_language(ASM)
        list(APPEND AHK_SOURCES
            source/libx64call/x64call.s
            source/libx64call/x64stub.s
        )
    endif()
endif()

# Resource file for Windows
set(AHK_RESOURCES
    source/resources/AutoHotkey.rc
)

function(configure_ahk_executable target_name output_dir)
    target_include_directories(${target_name} PRIVATE
        source
        source/lib_pcre/pcre
    )

    target_compile_definitions(${target_name} PRIVATE
        PCRE_STATIC
    )

    target_link_libraries(${target_name} PRIVATE
        pcre16
        wsock32
        ws2_32   # getaddrinfo/freeaddrinfo (Debugger DBGp listener) on mingw; harmless on MSVC.
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

    if(MSVC)
        target_compile_options(${target_name} PRIVATE /W3 /MP)
        target_compile_definitions(${target_name} PRIVATE _CRT_SECURE_NO_WARNINGS)
        target_link_options(${target_name} PRIVATE /MANIFEST:NO)
        set_property(TARGET ${target_name} PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    endif()

    if(MINGW)
        target_compile_options(${target_name} PRIVATE -fpermissive)
        target_link_options(${target_name} PRIVATE -static -static-libgcc -static-libstdc++ -municode)
    endif()

    set_target_properties(${target_name} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/${output_dir}"
        RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_SOURCE_DIR}/${output_dir}_debug"
        RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_SOURCE_DIR}/${output_dir}"
    )
endfunction()

# Standard GUI executable.
add_executable(${OUTPUT_NAME} WIN32 ${AHK_SOURCES} ${AHK_RESOURCES})
configure_ahk_executable(${OUTPUT_NAME} bin)

# Harness test executable: console subsystem with the same WinMain entry point.
set(HARNESS_OUTPUT_NAME "${OUTPUT_NAME}Harness")
add_executable(${HARNESS_OUTPUT_NAME} ${AHK_SOURCES} ${AHK_RESOURCES})
configure_ahk_executable(${HARNESS_OUTPUT_NAME} bin_harness)
target_compile_definitions(${HARNESS_OUTPUT_NAME} PRIVATE AHK_HARNESS_CONSOLE)

if(MSVC)
    target_link_options(${HARNESS_OUTPUT_NAME} PRIVATE /SUBSYSTEM:CONSOLE /ENTRY:wWinMainCRTStartup)
elseif(MINGW)
    target_link_options(${HARNESS_OUTPUT_NAME} PRIVATE -municode -Wl,--subsystem,console)
endif()

if(MSVC)
    set_property(TARGET pcre16 PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

if(MINGW)
    target_compile_options(pcre16 PRIVATE -fpermissive)
endif()

message(STATUS "Building AutoHotkey with _ScriptGetLines support")
message(STATUS "Output: ${CMAKE_SOURCE_DIR}/bin/${OUTPUT_NAME}.exe")
message(STATUS "Harness test output: ${CMAKE_SOURCE_DIR}/bin_harness/${HARNESS_OUTPUT_NAME}.exe")
