cmake_minimum_required(VERSION 3.20)
project(WaveKeyboard LANGUAGES C CXX OBJC OBJCXX)
cmake_minimum_required(VERSION 3.16)
project(WavePlayer LANGUAGES CXX)

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
find_package(SDL2 REQUIRED)

add_executable(wave_player
    src/main.cpp
    src/VoiceManager.cpp
)

target_include_directories(wave_player
    PRIVATE
        ${SDL2_INCLUDE_DIRS}
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

if (TARGET SDL2::SDL2main)
    target_link_libraries(wave_player PRIVATE SDL2::SDL2main)
endif()

target_link_libraries(wave_player PRIVATE SDL2::SDL2)

