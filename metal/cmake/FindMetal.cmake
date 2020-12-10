function(add_metal_shader INPUT_FILE OUTPUT_FILE)
    add_custom_command(
        OUTPUT ${OUTPUT_FILE}
        # TODO: specify/don't hardcode -I,-W args etc.
        COMMAND xcrun -sdk macosx metal -c -Wall -Wextra -std=osx-metal2.0 ${CMAKE_CURRENT_LIST_DIR}/${INPUT_FILE} -o ${INPUT_FILE}.air && xcrun -sdk macosx metallib -o ${OUTPUT_FILE} ${INPUT_FILE}.air
        MAIN_DEPENDENCY ${INPUT_FILE}
    )
endfunction()

find_library(FRAMEWORK_METAL
    NAMES
        Metal
    PATHS
        ${CMAKE_OSX_SYSROOT}/System/Library
    PATH_SUFFIXES
        Frameworks
    NO_DEFAULT_PATH
)

if(${FRAMEWORK_METAL} STREQUAL FRAMEWORK_METAL-NOTFOUND)
    message(FATAL_ERROR ": Framework Metal not found")
else()
    set(METAL_FRAMEWORK "-framework Metal")
endif()

find_package_handle_standard_args(Metal
    DEFAULT_MSG
    METAL_FRAMEWORK
)
