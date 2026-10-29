cmake_minimum_required(VERSION 3.20)
project(wproxy_plasma_vpn LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
add_compile_definitions(QT_NO_KEYWORDS)

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
find_package(Qt6 6.8 REQUIRED COMPONENTS Core Widgets)
find_package(KF6CoreAddons REQUIRED)
find_package(KF6NetworkManagerQt REQUIRED)
find_package(KF6WidgetsAddons REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBNM REQUIRED IMPORTED_TARGET libnm)
find_library(PLASMANM_EDITOR_LIBRARY NAMES plasmanm_editor REQUIRED)
include(KDEInstallDirs6)

add_library(plasmanetworkmanagement_wproxyui MODULE wproxy.cpp)
set_target_properties(plasmanetworkmanagement_wproxyui PROPERTIES
    PREFIX ""
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/plugins/plasma/network/vpn")
target_link_libraries(plasmanetworkmanagement_wproxyui PRIVATE
    Qt6::Widgets KF6::CoreAddons KF6::NetworkManagerQt KF6::WidgetsAddons
    PkgConfig::LIBNM ${PLASMANM_EDITOR_LIBRARY})
install(TARGETS plasmanetworkmanagement_wproxyui DESTINATION "${KDE_INSTALL_PLUGINDIR}/plasma/network/vpn")
file(GENERATE OUTPUT "${CMAKE_BINARY_DIR}/installed-plugin-path"
    CONTENT "${KDE_INSTALL_FULL_PLUGINDIR}/plasma/network/vpn/plasmanetworkmanagement_wproxyui.so\n")

add_executable(test-plasma-vpn test-plugin.cpp)
target_link_libraries(test-plasma-vpn PRIVATE
    Qt6::Widgets KF6::CoreAddons KF6::NetworkManagerQt KF6::WidgetsAddons
    PkgConfig::LIBNM ${PLASMANM_EDITOR_LIBRARY})
enable_testing()
add_test(NAME native-plasma-vpn COMMAND test-plasma-vpn "${CMAKE_BINARY_DIR}/plugins")
set_tests_properties(native-plasma-vpn PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
