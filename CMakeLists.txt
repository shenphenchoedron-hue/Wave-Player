cmake_minimum_required(VERSION 3.16)
project(WavePlayer LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

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

