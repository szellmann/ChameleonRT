set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_CURRENT_LIST_DIR}/cmake")

find_package(Metal REQUIRED)

add_metal_shader(util.metal util.metallib)

add_library(render_metal
    render_metal.cpp
    util.metallib)

set_target_properties(render_metal PROPERTIES
	CXX_STANDARD 14
	CXX_STANDARD_REQUIRED ON)

if (REPORT_RAY_STATS)
	target_compile_options(render_metal PUBLIC
		-DREPORT_RAY_STATS=1)
endif()

target_link_libraries(render_metal PUBLIC
	util ${METAL_FRAMEWORK})

