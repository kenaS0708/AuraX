cmake_minimum_required(VERSION 3.22.1)

project(llama_cpp_dart_wrapper)

# 1. Setup OpenCL paths BEFORE adding llama.cpp
set(OPENCL_HEADERS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/OpenCL-Headers")

if (ANDROID)
    message(STATUS "Configuring for Android (OpenCL disabled for compatibility)...")
    # OpenCL disabled — not available on all devices
    set(OpenCL_FOUND FALSE CACHE BOOL "OpenCL found" FORCE)
    set(GGML_OPENCL OFF CACHE BOOL "GGML OpenCL" FORCE)
endif()

# 2. Add llama.cpp (This builds llama, ggml, and applies the -DGGML_OPENCL flags)
add_subdirectory(llama.cpp)

# 3. Define your wrapper library (mtmd)
if (ANDROID)
    find_library(log-lib log)

    add_library(mtmd SHARED
        llama.cpp/tools/mtmd/mtmd.cpp
        llama.cpp/tools/mtmd/mtmd-audio.cpp
        llama.cpp/tools/mtmd/clip.cpp
        llama.cpp/tools/mtmd/mtmd-image.cpp
        llama.cpp/tools/mtmd/mtmd-helper.cpp
        llama.cpp/tools/mtmd/models/cogvlm.cpp
        llama.cpp/tools/mtmd/models/conformer.cpp
        llama.cpp/tools/mtmd/models/deepseekocr.cpp
        llama.cpp/tools/mtmd/models/dotsocr.cpp
        llama.cpp/tools/mtmd/models/gemma4a.cpp
        llama.cpp/tools/mtmd/models/gemma4v.cpp
        llama.cpp/tools/mtmd/models/glm4v.cpp
        llama.cpp/tools/mtmd/models/hunyuanocr.cpp
        llama.cpp/tools/mtmd/models/internvl.cpp
        llama.cpp/tools/mtmd/models/kimik25.cpp
        llama.cpp/tools/mtmd/models/kimivl.cpp
        llama.cpp/tools/mtmd/models/llama4.cpp
        llama.cpp/tools/mtmd/models/llava.cpp
        llama.cpp/tools/mtmd/models/minicpmv.cpp
        llama.cpp/tools/mtmd/models/mobilenetv5.cpp
        llama.cpp/tools/mtmd/models/nemotron-v2-vl.cpp
        llama.cpp/tools/mtmd/models/paddleocr.cpp
        llama.cpp/tools/mtmd/models/pixtral.cpp
        llama.cpp/tools/mtmd/models/qwen2vl.cpp
        llama.cpp/tools/mtmd/models/qwen3a.cpp
        llama.cpp/tools/mtmd/models/qwen3vl.cpp
        llama.cpp/tools/mtmd/models/siglip.cpp
        llama.cpp/tools/mtmd/models/step3vl.cpp
        llama.cpp/tools/mtmd/models/whisper-enc.cpp
        llama.cpp/tools/mtmd/models/youtuvl.cpp
    )

    # Include directories
    target_include_directories(mtmd PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp/include"
        "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp/ggml/include"
        "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp/common"
        "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp/tools/mtmd"
        "${CMAKE_CURRENT_SOURCE_DIR}"
        "${OPENCL_HEADERS_DIR}"
    )

    # Link libraries
    target_link_libraries(mtmd 
        PUBLIC 
            llama 
            ggml
            ${log-lib}

    )

    find_package(Threads REQUIRED)
    target_link_libraries(mtmd PRIVATE Threads::Threads)
endif()