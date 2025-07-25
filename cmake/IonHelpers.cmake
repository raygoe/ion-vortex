# cmake/IonHelpers.cmake
# Shared CMake utilities for Ion Vortex

include_guard(GLOBAL)

# ──────────────────────────────────────────────────────────────────────────────
# ion_setup_build_environment
#   Configures the build environment for shared libraries with proper output paths
# ──────────────────────────────────────────────────────────────────────────────
function(ion_setup_build_environment)
    # Force single-configuration behavior on multi-config generators (MSVC)
    if(CMAKE_CONFIGURATION_TYPES)
        if(CMAKE_BUILD_TYPE)
            set(CMAKE_CONFIGURATION_TYPES "${CMAKE_BUILD_TYPE}" CACHE STRING "" FORCE)
        else()
            set(CMAKE_CONFIGURATION_TYPES "Debug" CACHE STRING "" FORCE)
            set(CMAKE_BUILD_TYPE "Debug" CACHE STRING "" FORCE)
        endif()
    endif()
    
    # Platform-appropriate default layout
    if(WIN32)
        # Windows: DLLs next to executables
        set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR} PARENT_SCOPE)
        set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR} PARENT_SCOPE)
        set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR} PARENT_SCOPE)
        # Override all configuration-specific directories
        foreach(config ${CMAKE_CONFIGURATION_TYPES})
            string(TOUPPER ${config} config_upper)
            set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_${config_upper} ${CMAKE_BINARY_DIR} PARENT_SCOPE)
            set(CMAKE_LIBRARY_OUTPUT_DIRECTORY_${config_upper} ${CMAKE_BINARY_DIR} PARENT_SCOPE)
            set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY_${config_upper} ${CMAKE_BINARY_DIR} PARENT_SCOPE)
        endforeach()
    else()
        # Unix: executables in root, libraries in lib/
        set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR} PARENT_SCOPE)
        set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib PARENT_SCOPE)
        set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib PARENT_SCOPE)
    endif()
    
    # Configure RPATH to check all possible locations
    set(CMAKE_SKIP_BUILD_RPATH FALSE PARENT_SCOPE)
    set(CMAKE_BUILD_WITH_INSTALL_RPATH FALSE PARENT_SCOPE)
    set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE PARENT_SCOPE)
    
    # Set RPATH to check multiple locations (in order of preference)
    if(APPLE)
        # Check: same dir, lib subdir, ../lib
        set(CMAKE_INSTALL_RPATH "@loader_path;@loader_path/lib;@loader_path/../lib" PARENT_SCOPE)
        set(CMAKE_BUILD_RPATH "@loader_path;@loader_path/lib;@loader_path/../lib" PARENT_SCOPE)
    elseif(UNIX)
        # Check: same dir, lib subdir, ../lib
        set(CMAKE_INSTALL_RPATH "$ORIGIN;$ORIGIN/lib;$ORIGIN/../lib" PARENT_SCOPE)
        set(CMAKE_BUILD_RPATH "$ORIGIN;$ORIGIN/lib;$ORIGIN/../lib" PARENT_SCOPE)
    endif()
    
    # Force static linking for all external dependencies
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build shared libraries" FORCE)
endfunction()

# ──────────────────────────────────────────────────────────────────────────────
# ion_add_library
#   Creates a library target with standard Ion Vortex settings
#   Automatically discovers sources based on standard layout:
#     - src/**/*.cpp for sources
#     - include/ion/${NAME}/**/*.h for public headers
#   
# Usage:
#   ion_add_library(
#     NAME core
#     DEPENDENCIES ion::build  # Other ion:: libraries only
#   )
# ──────────────────────────────────────────────────────────────────────────────
function(ion_add_library)
    cmake_parse_arguments(ARG
        ""  # options
        "NAME"  # one-value keywords
        "DEPENDENCIES"  # multi-value keywords
        ${ARGN}
    )

    if(NOT ARG_NAME)
        message(FATAL_ERROR "ion_add_library: NAME is required")
    endif()

    # Automatically discover sources
    file(GLOB_RECURSE _sources CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp"
    )
    
    file(GLOB_RECURSE _public_headers CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/include/ion/${ARG_NAME}/*.h"
    )

    if(NOT _sources)
        message(FATAL_ERROR "No sources found in ${CMAKE_CURRENT_SOURCE_DIR}/src/")
    endif()

    # Create the library target
    set(_target_name "ion_${ARG_NAME}")
    add_library(ion_${ARG_NAME} SHARED ${_sources} ${_public_headers})
    add_library(ion::${ARG_NAME} ALIAS ${_target_name})
    
    # Set shared library properties
    string(SUBSTRING ${ARG_NAME} 0 1 _first_letter)
    string(TOUPPER ${_first_letter} _first_letter)
    string(SUBSTRING ${ARG_NAME} 1 -1 _rest)
    set(_windows_name "Ion${_first_letter}${_rest}")
    
    set_target_properties(ion_${ARG_NAME} PROPERTIES
        VERSION ${PROJECT_VERSION}
        SOVERSION ${PROJECT_VERSION_MAJOR}
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN ON
        POSITION_INDEPENDENT_CODE ON
        # Windows-specific: Use Windows naming convention
        OUTPUT_NAME $<IF:$<PLATFORM_ID:Windows>,${_windows_name},ion-${ARG_NAME}>
        # Remove config-specific output directories
        RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
        RUNTIME_OUTPUT_DIRECTORY_DEBUG ${CMAKE_CURRENT_BINARY_DIR}
        RUNTIME_OUTPUT_DIRECTORY_RELEASE ${CMAKE_CURRENT_BINARY_DIR}
        LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
        LIBRARY_OUTPUT_DIRECTORY_DEBUG ${CMAKE_CURRENT_BINARY_DIR}
        LIBRARY_OUTPUT_DIRECTORY_RELEASE ${CMAKE_CURRENT_BINARY_DIR}
        ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
        ARCHIVE_OUTPUT_DIRECTORY_DEBUG ${CMAKE_CURRENT_BINARY_DIR}
        ARCHIVE_OUTPUT_DIRECTORY_RELEASE ${CMAKE_CURRENT_BINARY_DIR}
    )
    
    # Define export macro for this library
    string(TOUPPER ${ARG_NAME} _name_upper)
    target_compile_definitions(ion_${ARG_NAME}
        PRIVATE "ION_${_name_upper}_EXPORTS"
        PUBLIC "ION_SHARED_LIBS"
    )
    
    # Set up include directories
    target_include_directories(${_target_name}
        PUBLIC
            $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
            $<INSTALL_INTERFACE:include>
        PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/src
    )

    # Link dependencies - PUBLIC so they propagate
    if(ARG_DEPENDENCIES)
        target_link_libraries(${_target_name} PUBLIC ${ARG_DEPENDENCIES})
    endif()

    # Always link ion::build for compiler settings
    if(NOT "ion::build" IN_LIST ARG_DEPENDENCIES)
        target_link_libraries(${_target_name} PRIVATE ion::build)
    endif()

    # Enable unity build if requested
    if(CMAKE_UNITY_BUILD)
        set_target_properties(${_target_name} PROPERTIES
            UNITY_BUILD ON
            UNITY_BUILD_BATCH_SIZE 16
        )
    endif()

    # Store this library's external dependencies for later retrieval
    # This is needed because we need to collect ALL transitive deps for executables
    get_property(_ext_deps GLOBAL PROPERTY ION_${ARG_NAME}_EXTERNAL_DEPS)
    set_property(GLOBAL PROPERTY ION_${ARG_NAME}_EXTERNAL_DEPS "${_ext_deps}")

    # Ignore the STL dll-interface warnings MSVC generates. 
    if(MSVC)
        target_compile_options(ion_${ARG_NAME} PRIVATE
            /wd4251  # 'type' needs to have dll-interface
            /wd4275  # non dll-interface base class
            /wd5030  # unrecognized attribute (gnu::...)
        )
    endif()

    # Export for find_package support
    install(TARGETS ${_target_name}
        EXPORT IonTargets
        ARCHIVE DESTINATION lib
        RUNTIME DESTINATION bin
    )

    install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/include/ion/${ARG_NAME}/
        DESTINATION include/ion/${ARG_NAME}
        FILES_MATCHING PATTERN "*.h"
    )
endfunction()

# ──────────────────────────────────────────────────────────────────────────────
# ion_add_external_dependency
#   Registers an external dependency for a library
#   This must be called BEFORE ion_add_library
#   
# Usage:
#   ion_add_external_dependency(core glm::glm nlohmann_json::nlohmann_json)
# ──────────────────────────────────────────────────────────────────────────────
function(ion_add_external_dependency lib_name)
    # Store the external deps in a global property
    set_property(GLOBAL APPEND PROPERTY ION_${lib_name}_EXTERNAL_DEPS ${ARGN})
endfunction()

# ──────────────────────────────────────────────────────────────────────────────
# ion_collect_all_dependencies
#   Recursively collects all transitive dependencies (internal and external)
#   Used internally by ion_add_application and ion_add_test
# ──────────────────────────────────────────────────────────────────────────────
function(ion_collect_all_dependencies out_var)
    set(_all_deps)
    set(_all_external_deps)
    set(_processed_libs)
    set(_libs_to_process ${ARGN})

    while(_libs_to_process)
        list(POP_FRONT _libs_to_process _current_lib)
        
        # Skip if already processed
        if(_current_lib IN_LIST _processed_libs)
            continue()
        endif()
        
        list(APPEND _processed_libs ${_current_lib})
        
        # Only process ion:: libraries
        if(_current_lib MATCHES "^ion::")
            list(APPEND _all_deps ${_current_lib})
            
            # Get the library name without ion:: prefix
            string(REPLACE "ion::" "" _lib_name ${_current_lib})
            
            # Get this library's external dependencies
            get_property(_ext_deps GLOBAL PROPERTY ION_${_lib_name}_EXTERNAL_DEPS)
            if(_ext_deps)
                list(APPEND _all_external_deps ${_ext_deps})
            endif()
            
            # Get this library's dependencies
            if(TARGET ion_${_lib_name})
                get_target_property(_lib_deps ion_${_lib_name} INTERFACE_LINK_LIBRARIES)
                if(_lib_deps)
                    foreach(_dep ${_lib_deps})
                        if(_dep MATCHES "^ion::" AND NOT _dep IN_LIST _processed_libs)
                            list(APPEND _libs_to_process ${_dep})
                        endif()
                    endforeach()
                endif()
            endif()
        endif()
    endwhile()

    # Remove duplicates
    list(REMOVE_DUPLICATES _all_deps)
    if(_all_external_deps)
        list(REMOVE_DUPLICATES _all_external_deps)
    endif()

    # Return both internal and external deps
    set(${out_var} ${_all_deps} ${_all_external_deps} PARENT_SCOPE)
endfunction()

# ──────────────────────────────────────────────────────────────────────────────
# ion_add_application
#   Creates an executable target with standard Ion Vortex settings
#   Automatically discovers sources in src/
#   
# Usage:
#   ion_add_application(
#     NAME client
#     DEPENDENCIES ion::core ion::render ion::ui
#   )
# ──────────────────────────────────────────────────────────────────────────────
function(ion_add_application)
    cmake_parse_arguments(ARG
        ""
        "NAME"
        "DEPENDENCIES"
        ${ARGN}
    )

    if(NOT ARG_NAME)
        message(FATAL_ERROR "ion_add_application: NAME is required")
    endif()

    # Automatically discover sources
    file(GLOB_RECURSE _sources CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp"
    )

    if(NOT _sources)
        message(FATAL_ERROR "No sources found in ${CMAKE_CURRENT_SOURCE_DIR}/src/")
    endif()

    # Create the executable
    add_executable(${ARG_NAME} ${_sources})

    # Set output directories to avoid config subdirectories (MSVC)
    set_target_properties(${ARG_NAME} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}
        RUNTIME_OUTPUT_DIRECTORY_DEBUG ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}
        RUNTIME_OUTPUT_DIRECTORY_RELEASE ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}
        PDB_OUTPUT_DIRECTORY ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}
        PDB_OUTPUT_DIRECTORY_DEBUG ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}
        PDB_OUTPUT_DIRECTORY_RELEASE ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}
    )

    # Ignore the STL dll-interface warnings MSVC generates. 
    if(MSVC)
        target_compile_options(${ARG_NAME} PRIVATE
            /wd4251  # 'type' needs to have dll-interface
            /wd4275  # non dll-interface base class
            /wd5030  # unrecognized attribute (gnu::...)
        )
    endif()

    # Collect ALL transitive dependencies
    ion_collect_all_dependencies(_all_deps ${ARG_DEPENDENCIES})

    # Link all dependencies
    target_link_libraries(${ARG_NAME}
        PRIVATE
            ion::build
            ${_all_deps}
    )

    # Enable unity build if requested
    if(CMAKE_UNITY_BUILD)
        set_target_properties(${ARG_NAME} PROPERTIES
            UNITY_BUILD ON
            UNITY_BUILD_BATCH_SIZE 16
        )
    endif()

    # Windows: Copy DLLs to executable directory if using lib/ layout
    if(WIN32 AND CMAKE_LIBRARY_OUTPUT_DIRECTORY)
        set(_ion_deps)
        foreach(_dep IN LISTS ARG_DEPENDENCIES)
            if(_dep MATCHES "^ion::")
                string(REPLACE "ion::" "ion_" _target ${_dep})
                list(APPEND _ion_deps ${_target})
            endif()
        endforeach()
        
        foreach(_lib IN LISTS _ion_deps)
            add_custom_command(TARGET ${ARG_NAME} POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                $<TARGET_FILE:${_lib}>
                $<TARGET_FILE_DIR:${ARG_NAME}>
                COMMENT "Copying ${_lib} DLL to executable directory"
            )
        endforeach()
    endif()

    # Install the executable
    install(TARGETS ${ARG_NAME}
        RUNTIME DESTINATION bin
    )
endfunction()

# ──────────────────────────────────────────────────────────────────────────────
# ion_add_test
#   Creates a test executable with Catch2 support
#   Automatically discovers test sources
#   
# Usage:
#   ion_add_test(
#     NAME core_tests
#     DEPENDENCIES ion::core
#   )
# ──────────────────────────────────────────────────────────────────────────────
function(ion_add_test)
    cmake_parse_arguments(ARG
        ""
        "NAME"
        "DEPENDENCIES"
        ${ARGN}
    )

    if(NOT ARG_NAME)
        message(FATAL_ERROR "ion_add_test: NAME is required")
    endif()

    # Ensure Catch2 is available
    find_package(Catch2 CONFIG REQUIRED)

    # Automatically discover test sources
    file(GLOB_RECURSE _sources CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/*.cpp"
    )

    if(NOT _sources)
        message(FATAL_ERROR "No test sources found in ${CMAKE_CURRENT_SOURCE_DIR}/")
    endif()

    # Create test executable
    add_executable(${ARG_NAME} ${_sources})
    
    # Set output directories to avoid config subdirectories (MSVC)
    set_target_properties(${ARG_NAME} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
        RUNTIME_OUTPUT_DIRECTORY_DEBUG ${CMAKE_CURRENT_BINARY_DIR}
        RUNTIME_OUTPUT_DIRECTORY_RELEASE ${CMAKE_CURRENT_BINARY_DIR}
        PDB_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
        PDB_OUTPUT_DIRECTORY_DEBUG ${CMAKE_CURRENT_BINARY_DIR}
        PDB_OUTPUT_DIRECTORY_RELEASE ${CMAKE_CURRENT_BINARY_DIR}
    )

    # Ignore the STL dll-interface warnings MSVC generates. 
    if(MSVC)
        target_compile_options(${ARG_NAME} PRIVATE
            /wd4251  # 'type' needs to have dll-interface
            /wd4275  # non dll-interface base class
            /wd5030  # unrecognized attribute (gnu::...)
        )
    endif()

    # Collect ALL transitive dependencies
    ion_collect_all_dependencies(_all_deps ${ARG_DEPENDENCIES})

    # Link test framework and all dependencies
    target_link_libraries(${ARG_NAME}
        PRIVATE
            ion::build
            ${_all_deps}
            Catch2::Catch2WithMain
    )

    include(Catch)
    
    # On Windows, we need to ensure DLLs can be found during test discovery
    if(WIN32)
        # For test discovery, we need the DLL paths in the environment
        set(_dll_paths "")
        foreach(_dep IN LISTS ARG_DEPENDENCIES)
            if(_dep MATCHES "^ion::")
                string(REPLACE "ion::" "ion_" _target ${_dep})
                if(TARGET ${_target})
                    list(APPEND _dll_paths $<TARGET_FILE_DIR:${_target}>)
                endif()
            endif()
        endforeach()
        
        # Use DL_PATHS to set PATH environment variable during test discovery
        catch_discover_tests(${ARG_NAME}
            WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
            EXTRA_ARGS --reporter console --durations yes
            DL_PATHS ${_dll_paths}
        )
        
        # Also copy DLLs to test directory for running tests manually
        foreach(_dep IN LISTS ARG_DEPENDENCIES)
            if(_dep MATCHES "^ion::")
                string(REPLACE "ion::" "ion_" _target ${_dep})
                if(TARGET ${_target})
                    add_custom_command(TARGET ${ARG_NAME} POST_BUILD
                        COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        $<TARGET_FILE:${_target}>
                        $<TARGET_FILE_DIR:${ARG_NAME}>
                        COMMENT "Copying ${_target} DLL to test directory"
                    )
                endif()
            endif()
        endforeach()
    else()
        # On Unix, just use regular test discovery
        catch_discover_tests(${ARG_NAME}
            WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
            EXTRA_ARGS --reporter console --durations yes
        )
    endif()
endfunction()

# ──────────────────────────────────────────────────────────────────────────────
# ion_find_dependencies
#   Wrapper to find common external dependencies with consistent error handling
# ──────────────────────────────────────────────────────────────────────────────
macro(ion_find_dependencies)
    foreach(_dep ${ARGN})
        if(_dep STREQUAL "curl")
            find_package(CURL REQUIRED)
        elseif(_dep STREQUAL "glm")
            find_package(glm CONFIG REQUIRED)
        elseif(_dep STREQUAL "sodium")
            find_package(unofficial-sodium CONFIG REQUIRED)
        elseif(_dep STREQUAL "libuv")
            find_package(libuv CONFIG REQUIRED)
        elseif(_dep STREQUAL "json")
            find_package(nlohmann_json CONFIG REQUIRED)
        elseif(_dep STREQUAL "toml")
            find_package(tomlplusplus CONFIG REQUIRED)
        else()
            message(FATAL_ERROR "Unknown dependency: ${_dep}")
        endif()
    endforeach()
endmacro()

# ──────────────────────────────────────────────────────────────────────────────
# ion_setup_build_interface
#   Creates the ion::build interface target if not already present
# ──────────────────────────────────────────────────────────────────────────────
function(ion_setup_build_interface)
    if(TARGET ion::build)
        return()
    endif()

    add_library(ion_build INTERFACE)
    add_library(ion::build ALIAS ion_build)

    # C++ standard
    target_compile_features(ion_build INTERFACE cxx_std_23)

    # Compiler-specific flags
    if(MSVC)
        target_compile_options(ion_build INTERFACE
            /W4 /WX
            /permissive-
            /sdl
        )
        target_compile_definitions(ion_build INTERFACE _WIN32_WINNT=0x0601)

        target_compile_options(ion_build INTERFACE
            $<$<CONFIG:Debug>:/Zi /Od>
            $<$<CONFIG:Release>:/O2 /DNDEBUG>
        )
    else()
        target_compile_options(ion_build INTERFACE
            -Wall -Wextra -Wunused-result -Werror
        )

        target_compile_options(ion_build INTERFACE
            $<$<CONFIG:Debug>:-g3 -O0 -fsanitize=address -fsanitize=undefined>
        )
        target_link_options(ion_build INTERFACE
            $<$<CONFIG:Debug>:-fsanitize=address -fsanitize=undefined>
        )

        target_compile_options(ion_build INTERFACE
            $<$<CONFIG:Release>:-O3 -DNDEBUG>
            $<$<AND:$<CONFIG:Release>,$<BOOL:${ION_ENABLE_MARCH_NATIVE}>>:-march=native>
        )
    endif()

    # install build-interface so that each library's public dependencies are satisfied
    install(TARGETS ion_build
        EXPORT IonTargets
        INCLUDES DESTINATION include
    )
endfunction()