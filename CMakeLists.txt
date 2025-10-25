cmake_minimum_required(VERSION 3.20)
project(WaveKeyboard LANGUAGES C CXX OBJC OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_OBJCXX_FLAGS "${CMAKE_OBJCXX_FLAGS} -fobjc-arc")
set(CMAKE_OSX_DEPLOYMENT_TARGET "10.15")

set(SOURCES
    src/main.mm
    src/SamplePlayer.mm
)

add_executable(WaveKeyboard MACOSX_BUNDLE ${SOURCES})

target_include_directories(WaveKeyboard PRIVATE include)

find_library(COCOA_FRAMEWORK Cocoa REQUIRED)
find_library(AVFOUNDATION_FRAMEWORK AVFoundation REQUIRED)
find_library(AUDIOTOOLBOX_FRAMEWORK AudioToolbox REQUIRED)

set_target_properties(WaveKeyboard PROPERTIES
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.example.wavekeyboard"
    MACOSX_BUNDLE_BUNDLE_NAME "Wave Keyboard"
    MACOSX_BUNDLE_LONG_VERSION_STRING "1.0"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0"
)

target_link_libraries(WaveKeyboard PRIVATE
    ${COCOA_FRAMEWORK}
    ${AVFOUNDATION_FRAMEWORK}
    ${AUDIOTOOLBOX_FRAMEWORK}
)
