add_library(
    clipboard
    clipboard.cpp
    clipboard.h
)
target_compile_features(clipboard PRIVATE cxx_std_20)
target_include_directories(clipboard PRIVATE ${MEMENTO_INCLUDE_DIRS})
target_compile_options(clipboard PRIVATE ${MEMENTO_COMPILER_FLAGS})
target_link_libraries(
    clipboard
    PRIVATE Qt6::Gui
    PUBLIC Qt6::Core
)

add_library(
    coloredimageprovider
    coloredimageprovider.cpp
    coloredimageprovider.h
)
target_compile_features(coloredimageprovider PRIVATE cxx_std_20)
target_include_directories(coloredimageprovider PRIVATE ${MEMENTO_INCLUDE_DIRS})
target_compile_options(coloredimageprovider PRIVATE ${MEMENTO_COMPILER_FLAGS})
target_link_libraries(
    coloredimageprovider
    PRIVATE Qt6::Gui
    PRIVATE Qt6::Svg
    PRIVATE utils
    PUBLIC Qt6::Quick
)

add_library(
    fileopenhandler
    fileopenhandler.cpp
    fileopenhandler.h
)
target_compile_features(fileopenhandler PRIVATE cxx_std_20)
target_include_directories(fileopenhandler PRIVATE ${MEMENTO_INCLUDE_DIRS})
target_compile_options(fileopenhandler PRIVATE ${MEMENTO_COMPILER_FLAGS})
target_link_libraries(
    fileopenhandler
    PRIVATE Qt6::Gui
    PUBLIC Qt6::Core
)

add_library(
    features
    features.cpp
    features.h
)
target_compile_features(features PRIVATE cxx_std_20)
target_include_directories(features PRIVATE ${MEMENTO_INCLUDE_DIRS})
target_compile_options(features PRIVATE ${MEMENTO_COMPILER_FLAGS})
target_link_libraries(
    features
    PRIVATE version
    PUBLIC Qt6::Core
)

add_library(
    furiganaparser
    furiganaparser.cpp
    furiganaparser.h
)
target_compile_features(furiganaparser PRIVATE cxx_std_20)
target_include_directories(furiganaparser PRIVATE ${MEMENTO_INCLUDE_DIRS})
target_compile_options(furiganaparser PRIVATE ${MEMENTO_COMPILER_FLAGS})
target_link_libraries(
    furiganaparser
    PRIVATE utils
    PUBLIC Qt6::Core
    PUBLIC settings
)
if(MEMENTO_MECAB_SUPPORT)
    target_link_libraries(
        furiganaparser
        PUBLIC MeCab::MeCab
    )
endif()

add_library(
    keytracker
    keytracker.cpp
    keytracker.h
)
target_compile_features(keytracker PRIVATE cxx_std_20)
target_include_directories(keytracker PRIVATE ${MEMENTO_INCLUDE_DIRS})
target_compile_options(keytracker PRIVATE ${MEMENTO_COMPILER_FLAGS})
target_link_libraries(
    keytracker
    PRIVATE Qt6::Gui
    PUBLIC Qt6::Core
)


add_library(
    quickpaths
    paths.cpp
    paths.h
)
target_compile_features(quickpaths PRIVATE cxx_std_20)
target_include_directories(quickpaths PRIVATE ${MEMENTO_INCLUDE_DIRS})
target_compile_options(quickpaths PRIVATE ${MEMENTO_COMPILER_FLAGS})
target_link_libraries(
    quickpaths
    PUBLIC Qt6::Core
    PUBLIC utils
)

add_library(
    togglclient
    togglclient.cpp
    togglclient.h
)
target_compile_features(togglclient PRIVATE cxx_std_20)
target_include_directories(togglclient PRIVATE ${MEMENTO_INCLUDE_DIRS})
target_compile_options(togglclient PRIVATE ${MEMENTO_COMPILER_FLAGS})
target_link_libraries(
    togglclient
    PUBLIC Qt6::Core
    PUBLIC Qt6::Network
    PRIVATE utils
)

add_library(
    subfiles
    subfiles.cpp
    subfiles.h
)
target_compile_features(subfiles PRIVATE cxx_std_20)
target_include_directories(subfiles PRIVATE ${MEMENTO_INCLUDE_DIRS})
target_compile_options(subfiles PRIVATE ${MEMENTO_COMPILER_FLAGS})
target_link_libraries(
    subfiles
    PUBLIC Qt6::Core
)

add_library(
    watchhistory
    watchhistory.cpp
    watchhistory.h
)
target_compile_features(watchhistory PRIVATE cxx_std_20)
target_include_directories(watchhistory PRIVATE ${MEMENTO_INCLUDE_DIRS})
target_compile_options(watchhistory PRIVATE ${MEMENTO_COMPILER_FLAGS})
target_link_libraries(
    watchhistory
    PUBLIC Qt6::Core
    PUBLIC Qt6::Network
    PRIVATE utils
)

add_library(
    malclient
    malclient.cpp
    malclient.h
)
target_compile_features(malclient PRIVATE cxx_std_20)
target_include_directories(malclient PRIVATE ${MEMENTO_INCLUDE_DIRS})
target_compile_options(malclient PRIVATE ${MEMENTO_COMPILER_FLAGS})
target_link_libraries(
    malclient
    PUBLIC Qt6::Core
    PUBLIC Qt6::Network
    PRIVATE Qt6::Gui
    PRIVATE utils
)

add_library(
    mangalibrary
    mangalibrary.cpp
    mangalibrary.h
)
target_compile_features(mangalibrary PRIVATE cxx_std_20)
target_include_directories(mangalibrary PRIVATE ${MEMENTO_INCLUDE_DIRS})
target_compile_options(mangalibrary PRIVATE ${MEMENTO_COMPILER_FLAGS})
target_link_libraries(
    mangalibrary
    PUBLIC Qt6::Core
    PRIVATE utils
)

add_library(
    gamepad
    gamepad.cpp
    gamepad.h
)
target_compile_features(gamepad PRIVATE cxx_std_20)
target_include_directories(gamepad PRIVATE ${MEMENTO_INCLUDE_DIRS})
target_compile_options(gamepad PRIVATE ${MEMENTO_COMPILER_FLAGS})
target_link_libraries(
    gamepad
    PUBLIC Qt6::Core
    PRIVATE Qt6::Gui
    PRIVATE Qt6::Quick
)
