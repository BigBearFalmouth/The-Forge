/*
 * Copyright (c) 2018 Confetti Interactive Inc.
 *
 * This file is part of The-Forge
 * (see https://github.com/ConfettiFX/The-Forge).
 *
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
*/

#ifdef METAL

#define RENDERER_IMPLEMENTATION
#define MAX_FRAMES_IN_FLIGHT 3

#if !defined(__APPLE__) && !defined(TARGET_OS_MAC)
#error "MacOs is needed!"
#endif
#import <simd/simd.h>
#import <MetalKit/MetalKit.h>

#import "../IRenderer.h"
#include "../IMemoryAllocator.h"
#include "../../OS/Interfaces/IMemoryManager.h"
#include "../../OS/Interfaces/ILogManager.h"

#define VALIDATE_IOS_MIN_VERSION(MIN_VER)    defined(TARGET_IOS) && __IPHONE_OS_VERSION_MIN_REQUIRED >= MIN_VER
#define VERTEX_SHADER   0
#define FRAGMENT_SHADER 1
#define COMPUTE_SHADER  2
#define MAX_BUFFER_BINDINGS 31

#ifdef TARGET_IOS
using NativeScreenType = UIScreen;
#else
using NativeScreenType = NSScreen;
#endif

// Constanat definitions

const unsigned int gPvrTc2MinTexWidth = 16;
const unsigned int gPvrTc2MinTexHeight = 8;
const unsigned int gPvrTc4MinTexHeight = 8;

const uint32_t MAX_DESCRIPTOR_SET_POOL_SIZE = 256;

// Global variables
float retinaScaling = 1.0f;
Mutex rootConstantMutex;
Mutex argumentBufferMutex;

#if defined(__cplusplus) && defined(RENDERER_CPP_NAMESPACE)
namespace RENDERER_CPP_NAMESPACE {
#endif
    
    MTLBlendOperation gMtlBlendOpTranslator[BlendMode::MAX_BLEND_MODES] =
    {
        MTLBlendOperationAdd,
        MTLBlendOperationSubtract,
        MTLBlendOperationReverseSubtract,
        MTLBlendOperationMin,
        MTLBlendOperationMax,
    };
    
    MTLBlendFactor gMtlBlendConstantTranslator[BlendConstant::MAX_BLEND_CONSTANTS] =
    {
        MTLBlendFactorZero,
        MTLBlendFactorOne,
        MTLBlendFactorSourceColor,
        MTLBlendFactorOneMinusSourceColor,
        MTLBlendFactorDestinationColor,
        MTLBlendFactorOneMinusDestinationColor,
        MTLBlendFactorSourceAlpha,
        MTLBlendFactorOneMinusSourceAlpha,
        MTLBlendFactorDestinationAlpha,
        MTLBlendFactorOneMinusDestinationAlpha,
        MTLBlendFactorSourceAlphaSaturated,
        MTLBlendFactorBlendColor,
        MTLBlendFactorOneMinusBlendColor,
        //MTLBlendFactorBlendAlpha,
        //MTLBlendFactorOneMinusBlendAlpha,
        //MTLBlendFactorSource1Color,
        //MTLBlendFactorOneMinusSource1Color,
        //MTLBlendFactorSource1Alpha,
        //MTLBlendFactorOneMinusSource1Alpha,
    };
    
    MTLCompareFunction gMtlComparisonFunctionTranslator[CompareMode::MAX_COMPARE_MODES] =
    {
        MTLCompareFunctionNever,
        MTLCompareFunctionLess,
        MTLCompareFunctionEqual,
        MTLCompareFunctionLessEqual,
        MTLCompareFunctionGreater,
        MTLCompareFunctionNotEqual,
        MTLCompareFunctionGreaterEqual,
        MTLCompareFunctionAlways,
    };
    
    MTLStencilOperation gMtlStencilOpTranslator[StencilOp::MAX_STENCIL_OPS] = {
        MTLStencilOperationKeep,
        MTLStencilOperationZero,
        MTLStencilOperationReplace,
        MTLStencilOperationInvert,
        MTLStencilOperationIncrementWrap,
        MTLStencilOperationDecrementWrap,
        MTLStencilOperationIncrementClamp,
        MTLStencilOperationDecrementClamp,
    };
    
    MTLCullMode gMtlCullModeTranslator[CullMode::MAX_CULL_MODES] =
    {
        MTLCullModeNone,
        MTLCullModeBack,
        MTLCullModeFront,
    };
    
    MTLTriangleFillMode gMtlFillModeTranslator[FillMode::MAX_FILL_MODES] =
    {
        MTLTriangleFillModeFill,
        MTLTriangleFillModeLines,
    };
    
    static const MTLPixelFormat gMtlFormatTranslator[] =
    {
        MTLPixelFormatInvalid,
        
        MTLPixelFormatR8Unorm,
        MTLPixelFormatRG8Unorm,
        MTLPixelFormatInvalid, //RGB8 not directly supported
        MTLPixelFormatRGBA8Unorm,
        
        MTLPixelFormatR16Unorm,
        MTLPixelFormatRG16Unorm,
        MTLPixelFormatInvalid, //RGB16 not directly supported
        MTLPixelFormatRGBA16Unorm,
        
        MTLPixelFormatR8Snorm,
        MTLPixelFormatRG8Snorm,
        MTLPixelFormatInvalid, //RGB8S not directly supported
        MTLPixelFormatRGBA8Snorm,
        
        MTLPixelFormatR16Snorm,
        MTLPixelFormatRG16Snorm,
        MTLPixelFormatInvalid, //RGB16S not directly supported
        MTLPixelFormatRGBA16Snorm,
        
        MTLPixelFormatR16Float,
        MTLPixelFormatRG16Float,
        MTLPixelFormatInvalid, //RGB16F not directly supported
        MTLPixelFormatRGBA16Float,
        
        MTLPixelFormatR32Float,
        MTLPixelFormatRG32Float,
        MTLPixelFormatInvalid, //RGB32F not directly supported
        MTLPixelFormatRGBA32Float,
        
        MTLPixelFormatR16Sint,
        MTLPixelFormatRG16Sint,
        MTLPixelFormatInvalid, //RGB16I not directly supported
        MTLPixelFormatRGBA16Sint,
        
        MTLPixelFormatR32Sint,
        MTLPixelFormatRG32Sint,
        MTLPixelFormatInvalid, //RGG32I not directly supported
        MTLPixelFormatRGBA32Sint,
        
        MTLPixelFormatR16Uint,
        MTLPixelFormatRG16Uint,
        MTLPixelFormatInvalid, //RGB16UI not directly supported
        MTLPixelFormatRGBA16Uint,
        
        MTLPixelFormatR32Uint,
        MTLPixelFormatRG32Uint,
        MTLPixelFormatInvalid, //RGB32UI not directly supported
        MTLPixelFormatRGBA32Uint,
        
        MTLPixelFormatInvalid, //RGBE8 not directly supported
        MTLPixelFormatRGB9E5Float,
        MTLPixelFormatRG11B10Float,
        MTLPixelFormatInvalid, //B5G6R5 not directly supported
        MTLPixelFormatInvalid, //RGBA4 not directly supported
        MTLPixelFormatRGB10A2Unorm,
        
#ifndef TARGET_IOS
        MTLPixelFormatDepth16Unorm,
        MTLPixelFormatDepth24Unorm_Stencil8,
        MTLPixelFormatDepth24Unorm_Stencil8,
        MTLPixelFormatDepth32Float,
        
        MTLPixelFormatBC1_RGBA,
        MTLPixelFormatBC2_RGBA,
        MTLPixelFormatBC3_RGBA,
        MTLPixelFormatBC4_RUnorm,
        MTLPixelFormatBC5_RGUnorm,
#else
        MTLPixelFormatInvalid,
        MTLPixelFormatInvalid,
        MTLPixelFormatInvalid,
        MTLPixelFormatInvalid,
        
        MTLPixelFormatInvalid,
        MTLPixelFormatInvalid,
        MTLPixelFormatInvalid,
        MTLPixelFormatInvalid,
        MTLPixelFormatInvalid,
#endif
        
        // PVR formats
        MTLPixelFormatInvalid, // PVR_2BPP = 56,
        MTLPixelFormatInvalid, // PVR_2BPPA = 57,
        MTLPixelFormatInvalid, // PVR_4BPP = 58,
        MTLPixelFormatInvalid, // PVR_4BPPA = 59,
        MTLPixelFormatInvalid, // INTZ = 60,    // Nvidia hack. Supported on all DX10+ HW
        // XBox 360 specific fron buffer formats.
        MTLPixelFormatInvalid, // LE_XRGB8 = 61,
        MTLPixelFormatInvalid, // LE_ARGB8 = 62,
        MTLPixelFormatInvalid, // LE_X2RGB10 = 63,
        MTLPixelFormatInvalid, // LE_A2RGB10 = 64,
        // Compressed mobile forms
        MTLPixelFormatInvalid, // ETC1 = 65,    //    RGB
        MTLPixelFormatInvalid, // ATC = 66,    //    RGB
        MTLPixelFormatInvalid, // ATCA = 67,    //    RGBA, explicit alpha
        MTLPixelFormatInvalid, // ATCI = 68,    //    RGBA, interpolated alpha
        MTLPixelFormatInvalid, // RAWZ = 69, //depth only, Nvidia (requires recombination of data) //FIX IT: PS3 as well?
        MTLPixelFormatInvalid, // DF16 = 70, //depth only, Intel/AMD
        MTLPixelFormatInvalid, // STENCILONLY = 71, // stencil ony usage
        MTLPixelFormatInvalid, // GNF_BC1 = 72,
        MTLPixelFormatInvalid, // GNF_BC2 = 73,
        MTLPixelFormatInvalid, // GNF_BC3 = 74,
        MTLPixelFormatInvalid, // GNF_BC4 = 75,
        MTLPixelFormatInvalid, // GNF_BC5 = 76,
        MTLPixelFormatInvalid, // GNF_BC6 = 77,
        MTLPixelFormatInvalid, // GNF_BC7 = 78,
        // Reveser Form
        MTLPixelFormatBGRA8Unorm, // BGRA8 = 79,
        // Extend for DXGI
        MTLPixelFormatInvalid, // X8D24PAX32 = 80,
        MTLPixelFormatInvalid, // S8 = 81,
        MTLPixelFormatInvalid, // D16S8 = 82,
        MTLPixelFormatInvalid, // D32S8 = 83,
    };
    
    // =================================================================================================
    // IMPLEMENTATION
    // =================================================================================================
    
    #if defined(RENDERER_IMPLEMENTATION)
    
    #define SAFE_FREE(p_var)        \
    if(p_var) {               \
    conf_free((void*)p_var);      \
    }
    
    #if defined(__cplusplus)
    #define DECLARE_ZERO(type, var) \
    type var = {};
    #else
    #define DECLARE_ZERO(type, var) \
    type var = {0};
    #endif
    
    // Internal utility functions (may become external one day)
    uint64_t util_pthread_to_uint64(const pthread_t& value);
    MTLPixelFormat util_to_mtl_pixel_format(const ImageFormat::Enum &format, const bool &srgb);
    bool util_is_mtl_depth_pixel_format(const MTLPixelFormat &format);
    bool util_is_mtl_compressed_pixel_format(const MTLPixelFormat &format);
    MTLVertexFormat util_to_mtl_vertex_format(const ImageFormat::Enum &format);
    MTLLoadAction util_to_mtl_load_action(const LoadActionType &loadActionType);
    
    void util_adjust_buffer_slots(const char* srcCode, char* outString);
    void util_bind_root_constant(Cmd* pCmd, DescriptorManager* pManager, const DescriptorInfo* descInfo, const DescriptorData* descData);
    void util_bind_argument_buffer(Cmd* pCmd, DescriptorManager* pManager, const DescriptorInfo* descInfo, const DescriptorData* descData);
    void util_end_current_encoders(Cmd* pCmd);
    bool util_sync_encoders(Cmd* pCmd, const CmdPoolType& newEncoderType);
    
    void add_texture(Renderer* pRenderer, const TextureDesc* pDesc, Texture** ppTexture, const bool isRT = false);
    
    /************************************************************************/
    // Dynamic Memory Allocator
    /************************************************************************/
    typedef struct DynamicMemoryAllocator
    {
        /// Size of mapped resources to be created
        uint64_t mSize;
        /// Current offset in the used page
        uint64_t mCurrentPos;
        /// Buffer alignment
        uint64_t mAlignment;
        Buffer* pBuffer;
        
        Mutex* pAllocationMutex;
    } DynamicMemoryAllocator;
    
    void addBuffer(Renderer* pRenderer, const BufferDesc* pDesc, Buffer** pp_buffer);
    void removeBuffer(Renderer* pRenderer, Buffer* pBuffer);
    void addTexture(Renderer* pRenderer, const TextureDesc* pDesc, Texture** ppTexture);
    void removeTexture(Renderer* pRenderer, Texture* pTexture);
    
    void add_dynamic_memory_allocator(Renderer* pRenderer, uint64_t size, DynamicMemoryAllocator** ppAllocator)
    {
        ASSERT(pRenderer);
        
        DynamicMemoryAllocator* pAllocator = (DynamicMemoryAllocator*)conf_calloc(1, sizeof(*pAllocator));
        pAllocator->mCurrentPos = 0;
        pAllocator->mSize = size;
        pAllocator->pAllocationMutex = conf_placement_new<Mutex>(conf_calloc(1, sizeof(Mutex)));
        
        BufferDesc desc = {};
        desc.mUsage = (BufferUsage)(BUFFER_USAGE_INDEX | BUFFER_USAGE_VERTEX | BUFFER_USAGE_UNIFORM);
        desc.mMemoryUsage = RESOURCE_MEMORY_USAGE_CPU_TO_GPU;
        desc.mSize = pAllocator->mSize;
        desc.mFlags = BUFFER_CREATION_FLAG_PERSISTENT_MAP_BIT;
        addBuffer(pRenderer, &desc, &pAllocator->pBuffer);
        
        pAllocator->mAlignment = pRenderer->pActiveGpuSettings->mUniformBufferAlignment;
        
        *ppAllocator = pAllocator;
    }
    
    void remove_dynamic_memory_allocator(Renderer* pRenderer, DynamicMemoryAllocator* pAllocator)
    {
        ASSERT(pAllocator);
        
        removeBuffer(pRenderer, pAllocator->pBuffer);
        
        pAllocator->pAllocationMutex->~Mutex();
        conf_free(pAllocator->pAllocationMutex);
        
        SAFE_FREE(pAllocator);
    }
    
    void reset_dynamic_memory_allocator(DynamicMemoryAllocator* pAllocator)
    {
        ASSERT(pAllocator);
        pAllocator->mCurrentPos = 0;
    }
    
    void consume_dynamic_memory_allocator(DynamicMemoryAllocator* p_linear_allocator, uint64_t size, void** ppCpuAddress, uint64_t* pOffset, id<MTLBuffer> ppMtlBuffer)
    {
        MutexLock lock(*p_linear_allocator->pAllocationMutex);
        
        if (p_linear_allocator->mCurrentPos + size > p_linear_allocator->mSize)
            reset_dynamic_memory_allocator(p_linear_allocator);
        
        *ppCpuAddress = (uint8_t*)p_linear_allocator->pBuffer->pCpuMappedAddress + p_linear_allocator->mCurrentPos;
        *pOffset = p_linear_allocator->mCurrentPos;
        if (ppMtlBuffer)
            ppMtlBuffer = p_linear_allocator->pBuffer->mtlBuffer;
        
        // Increment position by multiple of 256 to use CBVs in same heap as other buffers
        p_linear_allocator->mCurrentPos += round_up_64(size, p_linear_allocator->mAlignment);
    }
    
    void consume_dynamic_memory_allocator_lock_free(DynamicMemoryAllocator* p_linear_allocator, uint64_t size, void** ppCpuAddress, uint64_t* pOffset, id<MTLBuffer> ppMtlBuffer)
    {
        if (p_linear_allocator->mCurrentPos + size > p_linear_allocator->mSize)
            reset_dynamic_memory_allocator(p_linear_allocator);
        
        *ppCpuAddress = (uint8_t*)p_linear_allocator->pBuffer->pCpuMappedAddress + p_linear_allocator->mCurrentPos;
        *pOffset = p_linear_allocator->mCurrentPos;
        if (ppMtlBuffer)
            ppMtlBuffer = p_linear_allocator->pBuffer->mtlBuffer;
        
        // Increment position by multiple of 256 to use CBVs in same heap as other buffers
        p_linear_allocator->mCurrentPos += round_up_64(size, p_linear_allocator->mAlignment);
    }
    
    /************************************************************************/
    // Globals
    /************************************************************************/
    static Texture* pDefault1DTexture = NULL;
    static Texture* pDefault1DTextureArray = NULL;
    static Texture* pDefault2DTexture = NULL;
    static Texture* pDefault2DTextureArray = NULL;
    static Texture* pDefault3DTexture = NULL;
    static Texture* pDefaultCubeTexture = NULL;
    static Texture* pDefaultCubeTextureArray = NULL;
    
    static Buffer* pDefaultBuffer = NULL;
    static Sampler* pDefaultSampler = NULL;
    
    static BlendState* pDefaultBlendState = NULL;
    static DepthState* pDefaultDepthState = NULL;
    static RasterizerState* pDefaultRasterizerState = NULL;
    
    static volatile uint64_t gBufferIds = 0;
    static volatile uint64_t gTextureIds = 0;
    static volatile uint64_t gSamplerIds = 0;
    
    /************************************************************************/
    // Descriptor Manager Implementation
    /************************************************************************/
    // Since there are no descriptor tables in Metal, we just hold a map of all descriptors.
    using DescriptorMap = tinystl::unordered_map<uint64_t, DescriptorInfo>;
    using ConstDescriptorMapIterator = tinystl::unordered_map<uint64_t, DescriptorInfo>::const_iterator;
    using DescriptorMapNode = tinystl::unordered_hash_node<uint64_t, DescriptorInfo>;
    using DescriptorNameToIndexMap = tinystl::unordered_map<uint32_t, uint32_t>;
    
    typedef struct DescriptorManager
    {
        /// The root signature associated with this descriptor manager.
        RootSignature*                                                                  pRootSignature;
        /// The descriptor data bound to the current rootSignature;
        DescriptorData*                                                                 pDescriptorDataArray;
        /// Array of flags to check whether a descriptor has already been bound.
        bool*                                                                           pBoundDescriptors;
        /// Map that holds the number of times each rootConstant is bound.
        tinystl::unordered_map<uint32_t, uint32_t>                                      mRootConstantBindingCountMap;
        /// Map that holds all the rootConstants bound by this descriptor manager for each root signature.
        tinystl::unordered_map<uint32_t, tinystl::vector<Buffer*>>                      mRootConstantBuffers;
        /// Map that holds all the argument buffers bound by this descriptor manager for each root signature.
        tinystl::unordered_map<uint32_t, Buffer*>                                       mArgumentBuffers;
    } DescriptorManager;
    
    Mutex gDescriptorMutex;
    
    void add_descriptor_manager(Renderer* pRenderer, RootSignature* pRootSignature, DescriptorManager** ppManager)
    {
        DescriptorManager* pManager = (DescriptorManager*)conf_calloc(1, sizeof(*pManager));
        pManager->pRootSignature = pRootSignature;
        
        // Allocate enough memory to hold all the necessary data for all the descriptors of this rootSignature.
        pManager->pDescriptorDataArray = (DescriptorData*)conf_calloc(pRootSignature->mDescriptorCount, sizeof(DescriptorData));
        pManager->pBoundDescriptors = (bool*)conf_calloc(pRootSignature->mDescriptorCount, sizeof(bool));
        
        // Fill all the descriptors in the rootSignature with their default values.
        for (uint32_t i = 0; i < pRootSignature->mDescriptorCount; ++i)
        {
            DescriptorInfo* descriptorInfo = &pRootSignature->pDescriptors[i];
            
            // Create a DescriptorData structure for a default resource.
            pManager->pDescriptorDataArray[i].pName = (const char*)conf_calloc(descriptorInfo->mDesc.name_size + 1, sizeof(char));
            memcpy((char*)pManager->pDescriptorDataArray[i].pName, descriptorInfo->mDesc.name, descriptorInfo->mDesc.name_size);
            pManager->pDescriptorDataArray[i].mIndex = i;
            pManager->pDescriptorDataArray[i].mCount = 1;
            pManager->pDescriptorDataArray[i].mOffset = 0;
            
            // Metal requires that the bound textures match the texture type present in the shader.
            Texture** ppDefaultTexture = nil;
            if(descriptorInfo->mDesc.type == DESCRIPTOR_TYPE_RW_TEXTURE || descriptorInfo->mDesc.type == DESCRIPTOR_TYPE_TEXTURE)
            {
                switch((MTLTextureType)descriptorInfo->mDesc.mtlTextureType){
                    case MTLTextureType1D: ppDefaultTexture = &pDefault1DTexture; break;
                    case MTLTextureType1DArray: ppDefaultTexture = &pDefault1DTextureArray; break;
                    case MTLTextureType2D: ppDefaultTexture = &pDefault2DTexture; break;
                    case MTLTextureType2DArray: ppDefaultTexture = &pDefault2DTextureArray; break;
                    case MTLTextureType3D: ppDefaultTexture = &pDefault3DTexture; break;
                    case MTLTextureTypeCube: ppDefaultTexture = &pDefaultCubeTexture; break;
                    case MTLTextureTypeCubeArray: ppDefaultTexture = &pDefaultCubeTextureArray; break;
                }
            }
            
            // Point to the appropiate default resource depending of the type of descriptor.
            switch(descriptorInfo->mDesc.type)
            {
                case DESCRIPTOR_TYPE_RW_TEXTURE:
                case DESCRIPTOR_TYPE_TEXTURE:
                    pManager->pDescriptorDataArray[i].ppTextures = ppDefaultTexture;
                    break;
                case DESCRIPTOR_TYPE_SAMPLER:
                    pManager->pDescriptorDataArray[i].ppSamplers = &pDefaultSampler;
                    break;
                case DESCRIPTOR_TYPE_ROOT_CONSTANT:
                    // Default root constants can be bound the same way buffers are.
                    pManager->pDescriptorDataArray[i].pRootConstant = &pDefaultBuffer;
                    break;
                case DESCRIPTOR_TYPE_UNIFORM_BUFFER:
                case DESCRIPTOR_TYPE_RW_BUFFER:
                case DESCRIPTOR_TYPE_BUFFER:{
                    pManager->pDescriptorDataArray[i].ppBuffers = &pDefaultBuffer;
                    break;
                }
            }
        }
        
        *ppManager = pManager;
    }
    
    void remove_descriptor_manager(Renderer* pRenderer, RootSignature* pRootSignature, DescriptorManager* pManager)
    {
        pManager->mRootConstantBindingCountMap.clear();
        pManager->mRootConstantBuffers.clear();
        pManager->mArgumentBuffers.clear();
        SAFE_FREE(pManager->pDescriptorDataArray);
        SAFE_FREE(pManager->pBoundDescriptors);
        SAFE_FREE(pManager);
    }
    
    // This function returns the descriptor manager belonging to this thread
    // If a descriptor manager does not exist for this thread, a new one is created
    // With this approach we make sure that descriptor binding is thread safe and lock conf_free at the same time
    DescriptorManager* get_descriptor_manager(Renderer* pRenderer, RootSignature* pRootSignature)
    {
        tinystl::unordered_hash_node<ThreadID, DescriptorManager*>* pNode = pRootSignature->pDescriptorManagerMap.find(Thread::GetCurrentThreadID()).node;
        if (pNode == NULL)
        {
            // Only need a lock when creating a new descriptor manager for this thread
            MutexLock lock(gDescriptorMutex);
            DescriptorManager* pManager = NULL;
            add_descriptor_manager(pRenderer, pRootSignature, &pManager);
            pRootSignature->pDescriptorManagerMap.insert({ Thread::GetCurrentThreadID(), pManager });
            return pManager;
        }
        else
        {
            return pNode->second;
        }
    }
    
    const DescriptorInfo* get_descriptor(const RootSignature* pRootSignature, const char* pResName, uint32_t* pIndex)
    {
        DescriptorNameToIndexMap::const_iterator it = pRootSignature->pDescriptorNameToIndexMap.find(tinystl::hash(pResName));
        if (it.node)
        {
            *pIndex = it.node->second;
            return &pRootSignature->pDescriptors[it.node->second];
        }
        else
        {
            LOGERRORF("Invalid descriptor param (%s)", pResName);
            return NULL;
        }
    }
    
    void reset_bound_resources(DescriptorManager* pManager)
    {
        for (uint32_t i = 0; i < pManager->pRootSignature->mDescriptorCount; ++i)
        {
            DescriptorInfo* descInfo = &pManager->pRootSignature->pDescriptors[i];
            
            // Metal requires that the bound textures match the texture type present in the shader.
            Texture** ppDefaultTexture = nil;
            if(descInfo->mDesc.type == DESCRIPTOR_TYPE_RW_TEXTURE || descInfo->mDesc.type == DESCRIPTOR_TYPE_TEXTURE)
            {
                switch((MTLTextureType)descInfo->mDesc.mtlTextureType){
                    case MTLTextureType1D: ppDefaultTexture = &pDefault1DTexture; break;
                    case MTLTextureType1DArray: ppDefaultTexture = &pDefault1DTextureArray; break;
                    case MTLTextureType2D: ppDefaultTexture = &pDefault2DTexture; break;
                    case MTLTextureType2DArray: ppDefaultTexture = &pDefault2DTextureArray; break;
                    case MTLTextureType3D: ppDefaultTexture = &pDefault3DTexture; break;
                    case MTLTextureTypeCube: ppDefaultTexture = &pDefaultCubeTexture; break;
                    case MTLTextureTypeCubeArray: ppDefaultTexture = &pDefaultCubeTextureArray; break;
                }
            }
            
            switch(descInfo->mDesc.type)
            {
                case DESCRIPTOR_TYPE_RW_TEXTURE:
                case DESCRIPTOR_TYPE_TEXTURE:
                    pManager->pDescriptorDataArray[i].ppTextures = ppDefaultTexture;
                    break;
                case DESCRIPTOR_TYPE_SAMPLER:
                    pManager->pDescriptorDataArray[i].ppSamplers = &pDefaultSampler;
                    break;
                case DESCRIPTOR_TYPE_ROOT_CONSTANT:
                    pManager->pDescriptorDataArray[i].pRootConstant = &pDefaultBuffer;
                    break;
                case DESCRIPTOR_TYPE_UNIFORM_BUFFER:
                case DESCRIPTOR_TYPE_RW_BUFFER:
                case DESCRIPTOR_TYPE_BUFFER:{
                    pManager->pDescriptorDataArray[i].ppBuffers = &pDefaultBuffer;
                    break;
                }
            }
            pManager->pBoundDescriptors[i] = false;
        }
        pManager->mRootConstantBindingCountMap.clear(); // Also clear the root constants binding count map.
    }
    
    void cmdBindDescriptors(Cmd* pCmd, RootSignature* pRootSignature, uint32_t numDescriptors, DescriptorData* pDescParams)
    {
        ASSERT(pCmd);
        ASSERT(pRootSignature);
        
        Renderer* pRenderer = pCmd->pCmdPool->pRenderer;
        DescriptorManager* pManager = get_descriptor_manager(pRenderer, pRootSignature);
        
        // Compare the currently bound root signature with the root signature of the descriptor manager
        // If these values dont match, we must bind the root signature of the descriptor manager
        // If the values match, no op is required
        if (pCmd->pBoundRootSignature != pRootSignature)
        {
            // Bind the new root signature and reset its bound resources (if any).
            pCmd->pBoundRootSignature = pRootSignature;
            reset_bound_resources(pManager);
        }
        
        // Loop through input params to check for new data
        for (uint32_t paramIdx = 0; paramIdx < numDescriptors; ++paramIdx)
        {
            const DescriptorData* pParam = &pDescParams[paramIdx];
            ASSERT(pParam);
            if (!pParam->pName)
            {
                LOGERRORF("Name of Descriptor at index (%u) is NULL", paramIdx);
                return;
            }
            
            uint32_t hash = tinystl::hash(pParam->pName);
            uint32_t descIndex = -1;
            const DescriptorInfo* pDesc = get_descriptor(pRootSignature, pParam->pName, &descIndex);
            if (!pDesc)
                continue;
            
            // Replace the default DescriptorData by the new data pased into this function.
            pManager->pDescriptorDataArray[descIndex].pName = pParam->pName;
            pManager->pDescriptorDataArray[descIndex].mIndex = pParam->mIndex;
            pManager->pDescriptorDataArray[descIndex].mCount = pParam->mCount;
            pManager->pDescriptorDataArray[descIndex].mOffset = pParam->mOffset;
            switch(pDesc->mDesc.type)
            {
                case DESCRIPTOR_TYPE_RW_TEXTURE:
                case DESCRIPTOR_TYPE_TEXTURE:
                    if (!pParam->ppTextures) {
                        LOGERRORF("Texture descriptor (%s) is NULL", pParam->pName);
                        return;
                    }
                    pManager->pDescriptorDataArray[descIndex].ppTextures = pParam->ppTextures;
                    break;
                case DESCRIPTOR_TYPE_SAMPLER:
                    if (!pParam->ppSamplers) {
                        LOGERRORF("Sampler descriptor (%s) is NULL", pParam->pName);
                        return;
                    }
                    pManager->pDescriptorDataArray[descIndex].ppSamplers = pParam->ppSamplers;
                    break;
                case DESCRIPTOR_TYPE_ROOT_CONSTANT:
                    if (!pParam->pRootConstant) {
                        LOGERRORF("RootConstant array (%s) is NULL", pParam->pName);
                        return;
                    }
                    pManager->pDescriptorDataArray[descIndex].pRootConstant = pParam->pRootConstant;
                    
                    // Check if this rootConstant has previously been bound.
                    if (pManager->mRootConstantBindingCountMap.find(hash).node) pManager->mRootConstantBindingCountMap[hash]++;
                    else pManager->mRootConstantBindingCountMap[hash] = 0;
                    break;
                case DESCRIPTOR_TYPE_UNIFORM_BUFFER:
                case DESCRIPTOR_TYPE_RW_BUFFER:
                case DESCRIPTOR_TYPE_BUFFER:
                    if (!pParam->ppBuffers) {
                        LOGERRORF("Buffer descriptor (%s) is NULL", pParam->pName);
                        return;
                    }
                    pManager->pDescriptorDataArray[descIndex].ppBuffers = pParam->ppBuffers;
                    break;
            }
            
            // Mark this descriptor as unbound, so it's values are updated.
            pManager->pBoundDescriptors[descIndex] = false;
        }
        
        // If we're binding descriptors for a compute pipeline, we must ensure that we have a correct compute enconder recording commands.
        if(pCmd->pBoundRootSignature->mPipelineType == PIPELINE_TYPE_COMPUTE && !pCmd->mtlComputeEncoder)
        {
            util_end_current_encoders(pCmd);
            pCmd->mtlComputeEncoder = [pCmd->mtlCommandBuffer computeCommandEncoder];
        }
        
        // Bind all the unbound root signature descriptors.
        for (uint32_t i = 0; i < pRootSignature->mDescriptorCount; ++i)
        {
            const DescriptorInfo* descriptorInfo = &pRootSignature->pDescriptors[i];
            const DescriptorData* descriptorData = &pManager->pDescriptorDataArray[i];
            
            if(!pManager->pBoundDescriptors[i])
            {
                ShaderStage usedStagesMask = descriptorInfo->mDesc.used_stages;
                switch(descriptorInfo->mDesc.type)
                {
                    case DESCRIPTOR_TYPE_RW_TEXTURE:
                    case DESCRIPTOR_TYPE_TEXTURE:
                        if ((usedStagesMask & SHADER_STAGE_VERT) != 0)
                            [pCmd->mtlRenderEncoder setVertexTexture:descriptorData->ppTextures[0]->mtlTexture atIndex:descriptorInfo->mDesc.reg];
                        if ((usedStagesMask & SHADER_STAGE_FRAG) != 0)
                            [pCmd->mtlRenderEncoder setFragmentTexture:descriptorData->ppTextures[0]->mtlTexture atIndex:descriptorInfo->mDesc.reg];
                        if ((usedStagesMask & SHADER_STAGE_COMP) != 0)
                            [pCmd->mtlComputeEncoder setTexture:descriptorData->ppTextures[0]->mtlTexture atIndex:descriptorInfo->mDesc.reg];
                        break;
                    case DESCRIPTOR_TYPE_SAMPLER:
                        if ((usedStagesMask & SHADER_STAGE_VERT) != 0)
                            [pCmd->mtlRenderEncoder setVertexSamplerState:descriptorData->ppSamplers[0]->mtlSamplerState atIndex:descriptorInfo->mDesc.reg];
                        if ((usedStagesMask & SHADER_STAGE_FRAG) != 0)
                            [pCmd->mtlRenderEncoder setFragmentSamplerState:descriptorData->ppSamplers[0]->mtlSamplerState atIndex:descriptorInfo->mDesc.reg];
                        if ((usedStagesMask & SHADER_STAGE_COMP) != 0)
                            [pCmd->mtlComputeEncoder setSamplerState:descriptorData->ppSamplers[0]->mtlSamplerState atIndex:descriptorInfo->mDesc.reg];
                        break;
                    case DESCRIPTOR_TYPE_ROOT_CONSTANT:
                        util_bind_root_constant(pCmd, pManager, descriptorInfo, descriptorData);
                        break;
                    case DESCRIPTOR_TYPE_UNIFORM_BUFFER:
                    case DESCRIPTOR_TYPE_RW_BUFFER:
                    case DESCRIPTOR_TYPE_BUFFER:{
                        // If we're trying to bind a buffer with an mCount > 1, it means we're binding many descriptors into an argument buffer.
                        if (descriptorData->mCount > 1)
                        {
                            util_bind_argument_buffer(pCmd, pManager, descriptorInfo, descriptorData);
                        }
                        else
                        {
                            if ((usedStagesMask & SHADER_STAGE_VERT) != 0)
                                [pCmd->mtlRenderEncoder setVertexBuffer:descriptorData->ppBuffers[0]->mtlBuffer offset:(descriptorData->ppBuffers[0]->mPositionInHeap + descriptorData->mOffset) atIndex:descriptorInfo->mDesc.reg];
                            if ((usedStagesMask & SHADER_STAGE_FRAG) != 0)
                                [pCmd->mtlRenderEncoder setFragmentBuffer:descriptorData->ppBuffers[0]->mtlBuffer offset:(descriptorData->ppBuffers[0]->mPositionInHeap + descriptorData->mOffset) atIndex:descriptorInfo->mDesc.reg];
                            if ((usedStagesMask & SHADER_STAGE_COMP) != 0)
                                [pCmd->mtlComputeEncoder setBuffer:descriptorData->ppBuffers[0]->mtlBuffer offset:(descriptorData->ppBuffers[0]->mPositionInHeap + descriptorData->mOffset) atIndex:descriptorInfo->mDesc.reg];
                        }
                        break;
                    }
                }
                pManager->pBoundDescriptors[i] = true;
            }
        }
    }
    
    /************************************************************************/
    // Logging
    /************************************************************************/
    // Proxy log callback
    static void internal_log(LogType type, const char* msg, const char* component)
    {
        switch (type)
        {
            case LOG_TYPE_INFO:
                LOGINFOF("%s ( %s )", component, msg);
                break;
            case LOG_TYPE_WARN:
                LOGWARNINGF("%s ( %s )", component, msg);
                break;
            case LOG_TYPE_DEBUG:
                LOGDEBUGF("%s ( %s )", component, msg);
                break;
            case LOG_TYPE_ERROR:
                LOGERRORF("%s ( %s )", component, msg);
                break;
            default:
                break;
        }
    }
    
    // Resource allocation statistics.
    void calculateMemoryStats(Renderer* pRenderer, char** stats)
    {
        resourceAllocBuildStatsString(pRenderer->pResourceAllocator, stats, 0);
    }
    void freeMemoryStats(Renderer* pRenderer, char* stats)
    {
        resourceAllocFreeStatsString(pRenderer->pResourceAllocator, stats);
    }
    
    /************************************************************************/
    // Create default resources to be used a null descriptors in case user does not specify some descriptors
    /************************************************************************/
    void create_default_resources(Renderer* pRenderer)
    {
        TextureDesc texture1DDesc = { TEXTURE_TYPE_1D, TEXTURE_CREATION_FLAG_NONE, 2, 2, 1, 0, 1, 0, 1, SAMPLE_COUNT_1, 0, ImageFormat::R8, ClearValue(), TEXTURE_USAGE_SAMPLED_IMAGE | TEXTURE_USAGE_UNORDERED_ACCESS, RESOURCE_STATE_COMMON, nullptr, false, false };
        addTexture(pRenderer, &texture1DDesc, &pDefault1DTexture);
        TextureDesc texture1DArrayDesc = { TEXTURE_TYPE_1D, TEXTURE_CREATION_FLAG_NONE, 2, 2, 1, 0, 2, 0, 1, SAMPLE_COUNT_1, 0, ImageFormat::R8, ClearValue(), TEXTURE_USAGE_SAMPLED_IMAGE | TEXTURE_USAGE_UNORDERED_ACCESS, RESOURCE_STATE_COMMON, nullptr, false, false };
        addTexture(pRenderer, &texture1DArrayDesc, &pDefault1DTextureArray);
        TextureDesc texture2DDesc = { TEXTURE_TYPE_2D, TEXTURE_CREATION_FLAG_NONE, 2, 2, 1, 0, 1, 0, 1, SAMPLE_COUNT_1, 0, ImageFormat::R8, ClearValue(), TEXTURE_USAGE_SAMPLED_IMAGE | TEXTURE_USAGE_UNORDERED_ACCESS, RESOURCE_STATE_COMMON, nullptr, false, false };
        addTexture(pRenderer, &texture2DDesc, &pDefault2DTexture);
        TextureDesc texture2DArrayDesc = { TEXTURE_TYPE_2D, TEXTURE_CREATION_FLAG_NONE, 2, 2, 1, 0, 2, 0, 1, SAMPLE_COUNT_1, 0, ImageFormat::R8, ClearValue(), TEXTURE_USAGE_SAMPLED_IMAGE | TEXTURE_USAGE_UNORDERED_ACCESS, RESOURCE_STATE_COMMON, nullptr, false, false };
        addTexture(pRenderer, &texture2DArrayDesc, &pDefault2DTextureArray);
        TextureDesc texture3DDesc = { TEXTURE_TYPE_3D, TEXTURE_CREATION_FLAG_NONE, 2, 2, 1, 0, 1, 0, 1, SAMPLE_COUNT_1, 0, ImageFormat::R8, ClearValue(), TEXTURE_USAGE_SAMPLED_IMAGE | TEXTURE_USAGE_UNORDERED_ACCESS, RESOURCE_STATE_COMMON, nullptr, false, false };
        addTexture(pRenderer, &texture3DDesc, &pDefault3DTexture);
        TextureDesc textureCubeDesc = { TEXTURE_TYPE_CUBE, TEXTURE_CREATION_FLAG_NONE, 2, 2, 1, 0, 1, 0, 1, SAMPLE_COUNT_1, 0, ImageFormat::R8, ClearValue(), TEXTURE_USAGE_SAMPLED_IMAGE | TEXTURE_USAGE_UNORDERED_ACCESS, RESOURCE_STATE_COMMON, nullptr, false, false };
        addTexture(pRenderer, &textureCubeDesc, &pDefaultCubeTexture);
        TextureDesc textureCubeArrayDesc = { TEXTURE_TYPE_CUBE, TEXTURE_CREATION_FLAG_NONE, 2, 2, 1, 0, 2, 0, 1, SAMPLE_COUNT_1, 0, ImageFormat::R8, ClearValue(), TEXTURE_USAGE_SAMPLED_IMAGE | TEXTURE_USAGE_UNORDERED_ACCESS, RESOURCE_STATE_COMMON, nullptr, false, false };
        addTexture(pRenderer, &textureCubeArrayDesc, &pDefaultCubeTextureArray);
        
        BufferDesc bufferDesc = {};
        bufferDesc.mUsage = BUFFER_USAGE_STORAGE_SRV | BUFFER_USAGE_STORAGE_UAV | BUFFER_USAGE_UNIFORM;
        bufferDesc.mMemoryUsage = RESOURCE_MEMORY_USAGE_GPU_ONLY;
        bufferDesc.mStartState = RESOURCE_STATE_COMMON;
        bufferDesc.mSize = sizeof(uint32_t);
        bufferDesc.mFirstElement = 0;
        bufferDesc.mElementCount = 1;
        bufferDesc.mStructStride = sizeof(uint32_t);
        addBuffer(pRenderer, &bufferDesc, &pDefaultBuffer);
        
        addSampler(pRenderer, &pDefaultSampler);
        
        addBlendState(&pDefaultBlendState, BC_ONE, BC_ZERO, BC_ONE, BC_ZERO, BM_ADD, BM_ADD, ALL, ALL);
        addDepthState(pRenderer, &pDefaultDepthState, false, true);
        addRasterizerState(&pDefaultRasterizerState, CullMode::CULL_MODE_BACK);
    }
    
    void destroy_default_resources(Renderer* pRenderer)
    {
        removeTexture(pRenderer, pDefault1DTexture);
        removeTexture(pRenderer, pDefault1DTextureArray);
        removeTexture(pRenderer, pDefault2DTexture);
        removeTexture(pRenderer, pDefault2DTextureArray);
        removeTexture(pRenderer, pDefault3DTexture);
        removeTexture(pRenderer, pDefaultCubeTexture);
        removeTexture(pRenderer, pDefaultCubeTextureArray);
        
        removeBuffer(pRenderer, pDefaultBuffer);
        removeSampler(pRenderer, pDefaultSampler);
        
        removeBlendState(pDefaultBlendState);
        removeDepthState(pDefaultDepthState);
        removeRasterizerState(pDefaultRasterizerState);
    }
    
    // -------------------------------------------------------------------------------------------------
    // API functions
    // -------------------------------------------------------------------------------------------------
    
    ImageFormat::Enum getRecommendedSwapchainFormat(bool hintHDR)
    {
        return ImageFormat::BGRA8;
    }

    void initRenderer(const char *appName, const RendererDesc* settings, Renderer** ppRenderer)
    {
        Renderer* pRenderer = (Renderer*)conf_calloc(1, sizeof(*pRenderer));
        ASSERT(pRenderer);
        
        // Copy settings
        memcpy(&(pRenderer->mSettings), settings, sizeof(*settings));
        
        // Initialize the Metal bits
        {
            // Get the systems default device.
#ifndef TARGET_IOS
            pRenderer->pDevice = MTLCreateSystemDefaultDevice();
#else
            pRenderer->pDevice = ((MTKView*)CFBridgingRelease(pRenderer->mSettings.pViewHandle)).device;
#endif
            
            // Get the Metal Layer.
#ifndef TARGET_IOS
            pRenderer->mMetalLayer = [CAMetalLayer layer];
            pRenderer->mMetalLayer.framebufferOnly = YES;
            pRenderer->mMetalLayer.drawsAsynchronously = TRUE;
            pRenderer->mMetalLayer.presentsWithTransaction = FALSE;
#endif
            
            // Set the default GPU settings.
            pRenderer->mNumOfGPUs = 1;
            pRenderer->mGpuSettings[0].mMaxVertexInputBindings = MAX_VERTEX_BINDINGS; // there are no special vertex buffers for input in Metal, only regular buffers
            pRenderer->mGpuSettings[0].mUniformBufferAlignment = 256;
            pRenderer->mGpuSettings[0].mMultiDrawIndirect = false; // multi draw indirect is not supported on Metal: only single draw indirect
            pRenderer->pActiveGpuSettings = &pRenderer->mGpuSettings[0];
            
            // Create a resource allocator.
            AllocatorCreateInfo info = { 0 };
            info.device = pRenderer->pDevice;
            //info.physicalDevice = pRenderer->pActiveGPU;
            createAllocator(&info, &pRenderer->pResourceAllocator);
            
            // Create default resources.
            create_default_resources(pRenderer);
            
            // Renderer is good! Assign it to result!
            *(ppRenderer) = pRenderer;
        }
    }

    void removeRenderer(Renderer* pRenderer)
    {
        ASSERT(pRenderer);
        destroyAllocator(pRenderer->pResourceAllocator);
#ifndef TARGET_IOS
        pRenderer->mMetalLayer = nil;
#endif
        pRenderer->pDevice = nil;
        SAFE_FREE(pRenderer);
    }
    
    void addFence(Renderer* pRenderer, Fence** ppFence, uint64 mFenceValue)
    {
        ASSERT(pRenderer);
        ASSERT(pRenderer->pDevice != nil);
        
        Fence* pFence = (Fence*)conf_calloc(1, sizeof(*pFence));
        ASSERT(pFence);
        
        pFence->pRenderer = pRenderer;
        pFence->pMtlSemaphore = dispatch_semaphore_create(0);
        pFence->mSubmitted = false;
        pFence->mCompleted = false;
        
        *ppFence = pFence;
    }
    void removeFence(Renderer *pRenderer, Fence* pFence)
    {
        ASSERT(pFence);
        SAFE_FREE(pFence);
    }
    
    void addSemaphore(Renderer *pRenderer, Semaphore** ppSemaphore)
    {
        ASSERT(pRenderer);
        
        Semaphore* pSemaphore = (Semaphore*)conf_calloc(1, sizeof(*pSemaphore));
        ASSERT(pSemaphore);
        
        pSemaphore->pMtlSemaphore = dispatch_semaphore_create(0);
        
        *ppSemaphore = pSemaphore;
    }
    void removeSemaphore(Renderer *pRenderer, Semaphore* pSemaphore)
    {
        ASSERT(pSemaphore);
        SAFE_FREE(pSemaphore);
    }
    
    void addQueue(Renderer* pRenderer, QueueDesc* pQDesc, Queue** ppQueue){
        ASSERT(pQDesc);
        
        Queue* pQueue = (Queue*)conf_calloc(1, sizeof(*pQueue));
        ASSERT(pQueue);
        
        pQueue->pRenderer = pRenderer;
        pQueue->mtlCommandQueue = [pRenderer->pDevice newCommandQueue];
        pQueue->pMtlSemaphore = dispatch_semaphore_create(0);
        
        ASSERT(pQueue->mtlCommandQueue != nil);
        
        *ppQueue = pQueue;
    }
    void removeQueue(Queue* pQueue){
        ASSERT(pQueue);
        pQueue->mtlCommandQueue = nil;
        SAFE_FREE(pQueue);
    }
    
    void addCmdPool(Renderer *pRenderer, Queue* pQueue, bool transient, CmdPool** ppCmdPool, CmdPoolDesc * pCmdPoolDesc)
    {
        ASSERT(pRenderer);
        ASSERT(pRenderer->pDevice != nil);
        
        CmdPool* pCmdPool = (CmdPool*)conf_calloc(1, sizeof(*pCmdPool));
        ASSERT(pCmdPool);
        
        if (pCmdPoolDesc == NULL)
        {
            pCmdPool->mCmdPoolDesc = { pQueue->mQueueDesc.mType };
        }
        else
        {
            pCmdPool->mCmdPoolDesc = *pCmdPoolDesc;
        }
        pCmdPool->pRenderer = pRenderer;
        pCmdPool->pQueue = pQueue;
        
        *ppCmdPool = pCmdPool;
    }
    void removeCmdPool(Renderer* pRenderer, CmdPool* pCmdPool)
    {
        ASSERT(pCmdPool);
        SAFE_FREE(pCmdPool);
    }
    
    void addCmd(CmdPool* pCmdPool, bool secondary, Cmd** ppCmd)
    {
        ASSERT(pCmdPool);
        ASSERT(pCmdPool->pRenderer->pDevice != nil);
        
        Cmd* pCmd = (Cmd*)conf_calloc(1, sizeof(*pCmd));
        ASSERT(pCmd);
        
        pCmd->pCmdPool = pCmdPool;
        pCmd->mtlEncoderFence = [pCmdPool->pRenderer->pDevice newFence];
        
        *ppCmd = pCmd;
    }
    void removeCmd(CmdPool* pCmdPool, Cmd* pCmd)
    {
        ASSERT(pCmd);
        pCmd->mtlEncoderFence = nil;
        pCmd->mtlCommandBuffer = nil;
        SAFE_FREE(pCmd);
    }
    
    void addCmd_n(CmdPool *pCmdPool, bool secondary, uint32_t cmdCount, Cmd*** pppCmd)
    {
        ASSERT(pppCmd);
        
        Cmd** ppCmd = (Cmd**)conf_calloc(cmdCount, sizeof(*ppCmd));
        ASSERT(ppCmd);
        
        for (uint32_t i = 0; i < cmdCount; ++i) {
            addCmd(pCmdPool, secondary, &(ppCmd[i]));
        }
        
        *pppCmd = ppCmd;
    }
    void removeCmd_n(CmdPool *pCmdPool, uint32_t cmdCount, Cmd** ppCmd)
    {
        ASSERT(ppCmd);
        
        for (uint32_t i = 0; i < cmdCount; ++i) {
            removeCmd(pCmdPool, ppCmd[i]);
        }
        
        SAFE_FREE(ppCmd);
    }
    
    void addSwapChain(Renderer* pRenderer, const SwapChainDesc* pDesc, SwapChain** ppSwapChain)
    {
        ASSERT(pRenderer);
        ASSERT(pDesc);
        ASSERT(ppSwapChain);
        
        SwapChain* pSwapChain = (SwapChain*)conf_calloc(1, sizeof(*pSwapChain));
        pSwapChain->mDesc = *pDesc;
        
        // Assign MTKView to the swapchain.
        pSwapChain->pMTKView = (MTKView*)CFBridgingRelease(pDesc->pWindow->handle);
        pSwapChain->pMTKView.device = pRenderer->pDevice;
        pSwapChain->pMTKView.autoresizesSubviews = TRUE;
#if !defined(TARGET_IOS)
        pSwapChain->pMTKView.wantsLayer = YES;
#endif
        
        // Set the view pixel format to match the swapchain's pixel format.
        pSwapChain->pMTKView.colorPixelFormat = util_to_mtl_pixel_format(pSwapChain->mDesc.mColorFormat, pSwapChain->mDesc.mSrgb);
        
        // Calculate the global retina scaling (shared across swapchains).
        retinaScaling = pSwapChain->pMTKView.drawableSize.width / pSwapChain->pMTKView.frame.size.width;
        
        // Create present command queues for the swapchain.
        pSwapChain->presentCommandQueue = [pRenderer->pDevice newCommandQueue];
        pSwapChain->presentCommandBuffer = [pSwapChain->presentCommandQueue commandBuffer];
        
        // Create the swapchain RT descriptor.
        RenderTargetDesc descColor = {};
        descColor.mType = RENDER_TARGET_TYPE_2D;
        descColor.mUsage = RENDER_TARGET_USAGE_COLOR;
        descColor.mWidth = pSwapChain->mDesc.mWidth;
        descColor.mHeight = pSwapChain->mDesc.mHeight;
        descColor.mDepth = 1;
        descColor.mArraySize = 1;
        descColor.mFormat = pSwapChain->mDesc.mColorFormat;
        descColor.mSrgb = pSwapChain->mDesc.mSrgb;
        descColor.mClearValue = pSwapChain->mDesc.mColorClearValue;
        descColor.mSampleCount = SAMPLE_COUNT_1;
        descColor.mSampleQuality = 0;
        
        // Swapchain RT creation happens during acquireNextImage, as we can only access the swapchain's current drawable.
        pSwapChain->ppSwapchainRenderTargets = (RenderTarget**)conf_calloc(pSwapChain->mDesc.mImageCount, sizeof(*pSwapChain->ppSwapchainRenderTargets));
        for (uint32_t i = 0; i < pSwapChain->mDesc.mImageCount; ++i) {
            void* drawableTexture = nullptr;
            //if(i == 0) drawableTexture = (void*)CFBridgingRetain(pSwapChain->pMTKView.currentDrawable.texture); // We only have access to the current drawable.
            addRenderTarget(pRenderer, &descColor, &pSwapChain->ppSwapchainRenderTargets[i], drawableTexture);
        }
        
        *ppSwapChain = pSwapChain;
    }
    
    void removeSwapChain(Renderer* pRenderer, SwapChain* pSwapChain)
    {
        ASSERT(pRenderer);
        ASSERT(pSwapChain);
        
        pSwapChain->presentCommandBuffer = nil;
        pSwapChain->presentCommandQueue = nil;
        
        for (uint32_t i = 0; i < pSwapChain->mDesc.mImageCount; ++i)
            removeRenderTarget(pRenderer, pSwapChain->ppSwapchainRenderTargets[i]);
        
        SAFE_FREE(pSwapChain->ppSwapchainRenderTargets);
        SAFE_FREE(pSwapChain);
    }
    
    void addBuffer(Renderer* pRenderer, const BufferDesc* pDesc, Buffer** ppBuffer)
    {
        ASSERT(pRenderer);
        ASSERT(pDesc);
        ASSERT(pDesc->mSize > 0);
        ASSERT(pRenderer->pDevice != nil);
        
        Buffer* pBuffer = (Buffer*)conf_calloc(1, sizeof(*pBuffer));
        ASSERT(pBuffer);
        pBuffer->pRenderer = pRenderer;
        pBuffer->mDesc = *pDesc;
        
        // Align the buffer size to multiples of the dynamic uniform buffer minimum size
        if (pBuffer->mDesc.mUsage & BUFFER_USAGE_UNIFORM)
        {
            uint64_t minAlignment = pRenderer->pActiveGpuSettings->mUniformBufferAlignment;
            pBuffer->mDesc.mSize = round_up_64(pBuffer->mDesc.mSize, minAlignment);
        }
        
        // Get the proper memory requiremnets for the given buffer.
        AllocatorMemoryRequirements mem_reqs = { 0 };
        mem_reqs.usage = (ResourceMemoryUsage)pBuffer->mDesc.mMemoryUsage;
        mem_reqs.flags = 0;
        if (pBuffer->mDesc.mFlags & BUFFER_CREATION_FLAG_OWN_MEMORY_BIT)
            mem_reqs.flags |= RESOURCE_MEMORY_REQUIREMENT_OWN_MEMORY_BIT;
        if (pBuffer->mDesc.mFlags & BUFFER_CREATION_FLAG_PERSISTENT_MAP_BIT)
            mem_reqs.flags |= RESOURCE_MEMORY_REQUIREMENT_PERSISTENT_MAP_BIT;
        
        BufferCreateInfo alloc_info = {pBuffer->mDesc.mSize};
        bool allocSuccess = createBuffer(pRenderer->pResourceAllocator, &alloc_info, &mem_reqs, pBuffer);
        ASSERT(allocSuccess);
        
        pBuffer->mBufferId = (++gBufferIds << 8U) + util_pthread_to_uint64(Thread::GetCurrentThreadID());
        pBuffer->mCurrentState = pBuffer->mDesc.mStartState;
        
        // If buffer is a suballocation use offset in heap else use zero offset (placed resource / committed resource)
        if (pBuffer->pMtlAllocation->GetResource())
            pBuffer->mPositionInHeap = pBuffer->pMtlAllocation->GetOffset();
        else
            pBuffer->mPositionInHeap = 0;
        
        *ppBuffer = pBuffer;
    }
    void removeBuffer(Renderer* pRenderer, Buffer* pBuffer)
    {
        ASSERT(pBuffer);
        destroyBuffer(pRenderer->pResourceAllocator, pBuffer);
        SAFE_FREE(pBuffer);
    }
    
    void addTexture(Renderer* pRenderer, const TextureDesc* pDesc, Texture** ppTexture)
    {
        ASSERT(pRenderer);
        ASSERT(pDesc && pDesc->mWidth && pDesc->mHeight && (pDesc->mDepth || pDesc->mArraySize));
        if (pDesc->mSampleCount > SAMPLE_COUNT_1 && pDesc->mMipLevels > 1)
        {
            LOGERROR("Multi-Sampled textures cannot have mip maps");
            ASSERT(false);
            return;
        }
        add_texture(pRenderer, pDesc, ppTexture, false);
    }
    
    void addRenderTarget(Renderer* pRenderer, const RenderTargetDesc* pDesc, RenderTarget** ppRenderTarget, void* pNativeHandle)
    {
        ASSERT(pRenderer);
        ASSERT(pDesc);
        ASSERT(ppRenderTarget);
        
        RenderTarget* pRenderTarget = (RenderTarget*)conf_calloc(1, sizeof(*pRenderTarget));
        pRenderTarget->mDesc = *pDesc;
        
        TextureDesc rtDesc = {
            TEXTURE_TYPE_2D, // TODO: Support different format RTs.
            TEXTURE_CREATION_FLAG_NONE,
            pRenderTarget->mDesc.mWidth, pRenderTarget->mDesc.mHeight, pRenderTarget->mDesc.mDepth,
            pRenderTarget->mDesc.mBaseArrayLayer, pRenderTarget->mDesc.mArraySize,
            0, 1, // TODO: Should we support multiple mips levels on an RT?
            pRenderTarget->mDesc.mSampleCount, pRenderTarget->mDesc.mSampleQuality,
            pRenderTarget->mDesc.mFormat, pRenderTarget->mDesc.mClearValue, TEXTURE_USAGE_SAMPLED_IMAGE,
            RESOURCE_STATE_UNDEFINED, pNativeHandle, pRenderTarget->mDesc.mSrgb, false
        };
        add_texture(pRenderer, &rtDesc, &pRenderTarget->pTexture, true);
        
        *ppRenderTarget = pRenderTarget;
    }
    void removeTexture(Renderer* pRenderer, Texture* pTexture)
    {
        ASSERT(pTexture);
        if (pTexture->mOwnsImage)
        {
            destroyTexture(pRenderer->pResourceAllocator, pTexture);
        }
        SAFE_FREE(pTexture);
    }
    void removeRenderTarget(Renderer* pRenderer, RenderTarget* pRenderTarget)
    {
        removeTexture(pRenderer, pRenderTarget->pTexture);
        SAFE_FREE(pRenderTarget);
    }
    
    void addSampler(Renderer* pRenderer, Sampler** ppSampler, FilterType minFilter, FilterType magFilter, MipMapMode  mipMapMode, AddressMode addressU, AddressMode addressV, AddressMode addressW, float mipLosBias, float maxAnisotropy)
    {
        ASSERT(pRenderer);
        ASSERT(pRenderer->pDevice != nil);
        
        Sampler* pSampler = (Sampler*)conf_calloc(1, sizeof(*pSampler));
        ASSERT(pSampler);
        pSampler->pRenderer = pRenderer;
        
        MTLSamplerDescriptor* samplerDesc = [[MTLSamplerDescriptor alloc] init];
        samplerDesc.minFilter = (minFilter == FILTER_NEAREST ? MTLSamplerMinMagFilterNearest : MTLSamplerMinMagFilterLinear);
        samplerDesc.magFilter = (minFilter == FILTER_NEAREST ? MTLSamplerMinMagFilterNearest : MTLSamplerMinMagFilterLinear);
        samplerDesc.mipFilter = (mipMapMode == MIPMAP_MODE_NEAREST ? MTLSamplerMipFilterNearest : MTLSamplerMipFilterLinear);
        samplerDesc.maxAnisotropy = (maxAnisotropy==0 ? 1 : maxAnisotropy);  // 0 is not allowed in Metal
        samplerDesc.sAddressMode = (addressU == ADDRESS_MODE_CLAMP_TO_EDGE ? MTLSamplerAddressModeClampToEdge : MTLSamplerAddressModeMirrorRepeat);
        samplerDesc.tAddressMode = (addressV == ADDRESS_MODE_CLAMP_TO_EDGE ? MTLSamplerAddressModeClampToEdge : MTLSamplerAddressModeMirrorRepeat);
        samplerDesc.rAddressMode = (addressW == ADDRESS_MODE_CLAMP_TO_EDGE ? MTLSamplerAddressModeClampToEdge : MTLSamplerAddressModeMirrorRepeat);
        pSampler->mtlSamplerState = [pRenderer->pDevice newSamplerStateWithDescriptor:samplerDesc];
        pSampler->mSamplerId = (++gSamplerIds << 8U) + util_pthread_to_uint64(Thread::GetCurrentThreadID());
        
        *ppSampler = pSampler;
    }
    void removeSampler(Renderer* pRenderer, Sampler* pSampler)
    {
        ASSERT(pSampler);
        pSampler->mtlSamplerState = nil;
        SAFE_FREE(pSampler);
    }
    
    void addShader(Renderer* pRenderer, const ShaderDesc* pDesc, Shader** ppShaderProgram)
    {
        ASSERT(pRenderer);
        ASSERT(pDesc);
        ASSERT(pRenderer->pDevice != nil);
        
        Shader* pShaderProgram = (Shader*)conf_calloc(1, sizeof(*pShaderProgram));
        pShaderProgram->pRenderer = pRenderer;
        pShaderProgram->mStages = pDesc->mStages;
        
        uint32_t shaderReflectionCounter = 0;
        ShaderReflection stageReflections[SHADER_STAGE_COUNT];
        for (uint32_t i = 0; i < SHADER_STAGE_COUNT; ++i)
        {
            ShaderStage stage_mask = (ShaderStage)(1 << i);
            if (stage_mask == (pShaderProgram->mStages & stage_mask)) {
                const char* source = NULL;
                const char* entry_point = NULL;
                const char* shader_name = NULL;
                tinystl::vector<ShaderMacro> shader_macros;
                __strong id<MTLFunction>* compiled_code = nullptr;
                switch (stage_mask) {
                    case SHADER_STAGE_VERT: {
                        source = pDesc->mVert.mCode.c_str();
                        entry_point = pDesc->mVert.mEntryPoint.c_str();
                        shader_name = pDesc->mVert.mName.c_str();
                        shader_macros = pDesc->mVert.mMacros;
                        compiled_code = &(pShaderProgram->mtlVertexShader);
                    } break;
                    case SHADER_STAGE_FRAG: {
                        source = pDesc->mFrag.mCode.c_str();
                        entry_point = pDesc->mFrag.mEntryPoint.c_str();
                        shader_name = pDesc->mFrag.mName.c_str();
                        shader_macros = pDesc->mFrag.mMacros;
                        compiled_code = &(pShaderProgram->mtlFragmentShader);
                    } break;
                    case SHADER_STAGE_COMP: {
                        source = pDesc->mComp.mCode.c_str();
                        entry_point = pDesc->mComp.mEntryPoint.c_str();
                        shader_name = pDesc->mComp.mName.c_str();
                        shader_macros = pDesc->mComp.mMacros;
                        compiled_code = &(pShaderProgram->mtlComputeShader);
                    } break;
                    default:
                        break;
                }
                
                char* parsedCode = (char*)conf_calloc(1, strlen(source)*2);
                util_adjust_buffer_slots(source, parsedCode);
                uint32_t parsedCodeSize = (uint32_t)strlen(parsedCode);
                
                tinystl::string definition;
                tinystl::string value;
                
                // Create a NSDictionary for all the shader macros.
                NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init]; // Used for reading NSNumbers macro values from strings.
                numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;
                
                NSArray* defArray = [[NSArray alloc] init];
                NSArray* valArray = [[NSArray alloc] init];
                for(uint i = 0; i < shader_macros.size(); i++)
                {
                    defArray = [defArray arrayByAddingObject:[[NSString alloc] initWithUTF8String:shader_macros[i].definition]];
                    
                    // Try reading the macro value as a NSNumber. If failed, use it as an NSString.
                    NSString* valueString = [[NSString alloc] initWithUTF8String:shader_macros[i].value];
                    NSNumber* valueNumber = [numberFormatter numberFromString:valueString];
                    if(valueNumber) valArray = [valArray arrayByAddingObject:valueNumber];
                    else valArray = [valArray arrayByAddingObject:valueString];
                }
                NSDictionary* macroDictionary = [[NSDictionary alloc] initWithObjects:valArray forKeys:defArray];
                
                // Compile the code
                NSString* shaderSource = [[NSString alloc] initWithUTF8String:parsedCode];
                NSError* error = nil;
                
#if VALIDATE_IOS_MIN_VERSION(__IPHONE_9_0) && !defined(TARGET_IOS)
                MTLCompileOptions* options = [MTLCompileOptions alloc];
                options.preprocessorMacros = macroDictionary;
                options.languageVersion = MTLLanguageVersion1_0;
                id<MTLLibrary> lib = [pRenderer->pDevice newLibraryWithSource:shaderSource options:options error:&error];
#else
                MTLCompileOptions* options = [[MTLCompileOptions alloc] init];
                options.preprocessorMacros = macroDictionary;
                //  TODO: iOS 9.0 beta 3 fails to compile the shader is options object is passed
                id<MTLLibrary> lib = [pRenderer->pDevice newLibraryWithSource:shaderSource options:options error:&error];
#endif  //  VALIDATE_IOS_MIN_VERSION(__IPHONE_9_0)
                
                if (error)
                {
                    NSLog(@ "%s %@", shader_name, error);
                    error = 0;  //  error string is an autorelease object.
                }
                
                if (lib)
                {
                    NSString* entryPointNStr = [[NSString alloc] initWithUTF8String:entry_point];
                    id<MTLFunction> function = [lib newFunctionWithName:entryPointNStr];
                    assert(function!=nil && "Entry point not found in shader.");
                    *compiled_code = function;
                }
                
                createShaderReflection(pShaderProgram, (const uint8_t*)parsedCode, parsedCodeSize, stage_mask, &stageReflections[shaderReflectionCounter++]);
                
                conf_free(parsedCode);
            }
        }
        
        createPipelineReflection(stageReflections, shaderReflectionCounter, &pShaderProgram->mReflection);
        
        *ppShaderProgram = pShaderProgram;
    }
    
    void removeShader(Renderer* pRenderer, Shader* pShaderProgram)
    {
        ASSERT(pShaderProgram);
        pShaderProgram->mtlVertexShader = nil;
        pShaderProgram->mtlFragmentShader = nil;
        pShaderProgram->mtlComputeShader = nil;
        SAFE_FREE(pShaderProgram);
    }
    
    void addRootSignature(Renderer* pRenderer, uint32_t numShaders, Shader* const* ppShaders, RootSignature** ppRootSignature, const RootSignatureDesc* pRootDesc)
    {
        ASSERT(pRenderer);
        ASSERT(pRenderer->pDevice != nil);
        
        RootSignature* pRootSignature = (RootSignature*)conf_calloc(1, sizeof(*pRootSignature));
        tinystl::vector<ShaderResource const*> shaderResources;
        
        conf_placement_new<tinystl::unordered_map<uint32_t, uint32_t>>(&pRootSignature->pDescriptorNameToIndexMap);
        
        // Collect all unique shader resources in the given shaders
        // Resources are parsed by name (two resources named "XYZ" in two shaders will be considered the same resource)
        for (uint32_t sh = 0; sh < numShaders; ++sh)
        {
            PipelineReflection const* pReflection = &ppShaders[sh]->mReflection;
            
            if (pReflection->mShaderStages & SHADER_STAGE_COMP)
                pRootSignature->mPipelineType = PIPELINE_TYPE_COMPUTE;
            else
                pRootSignature->mPipelineType = PIPELINE_TYPE_GRAPHICS;
            
            for (uint32_t i = 0; i < pReflection->mShaderResourceCount; ++i)
            {
                ShaderResource const* pRes = &pReflection->pShaderResources[i];
                uint32_t setIndex = 0; // NOTE: Resource Update Frequency is ignored on Metal.
                
                // Find all unique resources
                tinystl::unordered_hash_node<uint32_t, uint32_t>* pNode = pRootSignature->pDescriptorNameToIndexMap.find(tinystl::hash(pRes->name)).node;
                if (!pNode)
                {
                    pRootSignature->pDescriptorNameToIndexMap.insert({ tinystl::hash(pRes->name), shaderResources.getCount() });
                    shaderResources.emplace_back(pRes);
                }
            }
        }
        
        if (shaderResources.getCount())
        {
            pRootSignature->mDescriptorCount = shaderResources.getCount();
            pRootSignature->pDescriptors = (DescriptorInfo*)conf_calloc(pRootSignature->mDescriptorCount, sizeof(DescriptorInfo));
        }
        
        // Fill the descriptor array to be stored in the root signature
        for (uint32_t i = 0; i < shaderResources.getCount(); ++i)
        {
            DescriptorInfo* pDesc = &pRootSignature->pDescriptors[i];
            ShaderResource const* pRes = shaderResources[i];
            uint32_t setIndex = pRes->set;
            DescriptorUpdateFrequency updateFreq = (DescriptorUpdateFrequency)setIndex;
            
            pDesc->mDesc.reg = pRes->reg;
            pDesc->mDesc.set = pRes->set;
            pDesc->mDesc.size = pRes->size;
            pDesc->mDesc.type = pRes->type;
            pDesc->mDesc.used_stages = pRes->used_stages;
            pDesc->mDesc.name_size = pRes->name_size;
            pDesc->mDesc.name = (const char*)conf_calloc(pDesc->mDesc.name_size + 1, sizeof(char));
            memcpy((char*)pDesc->mDesc.name, pRes->name, pRes->name_size);
            pDesc->mUpdateFrquency = updateFreq;
            
            // In case we're binding a texture, we need to specify the texture type so the bound resource type matches the one defined in the shader.
            if(pRes->type == DESCRIPTOR_TYPE_TEXTURE || pRes->type == DESCRIPTOR_TYPE_RW_TEXTURE)
            {
                pDesc->mDesc.mtlTextureType = pRes->mtlTextureType;
            }
            
            // If we're binding an argument buffer, we also need to get the type of the resources that this buffer will store.
            if(pRes->mtlArgumentBufferType != DESCRIPTOR_TYPE_UNDEFINED)
            {
                pDesc->mDesc.mtlArgumentBufferType = pRes->mtlArgumentBufferType;
            }
        }
        
        // Create descriptor manager for this thread.
        DescriptorManager* pManager = NULL;
        add_descriptor_manager(pRenderer, pRootSignature, &pManager);
        pRootSignature->pDescriptorManagerMap.insert({ Thread::GetCurrentThreadID(), pManager });
        
        *ppRootSignature = pRootSignature;
    }
    
    void removeRootSignature(Renderer* pRenderer, RootSignature* pRootSignature)
    {
        for (tinystl::unordered_hash_node<ThreadID, DescriptorManager*>& it : pRootSignature->pDescriptorManagerMap)
        {
            remove_descriptor_manager(pRenderer, pRootSignature, it.second);
        }
        
        pRootSignature->pDescriptorManagerMap.~unordered_map();
        
        pRootSignature->pDescriptorNameToIndexMap.~unordered_map();
        
        SAFE_FREE(pRootSignature);
    }
    
    void addPipeline(Renderer* pRenderer, const GraphicsPipelineDesc* pDesc, Pipeline** ppPipeline)
    {
        ASSERT(pRenderer);
        ASSERT(pRenderer->pDevice != nil);
        ASSERT(pDesc);
        ASSERT(pDesc->pShaderProgram);
        ASSERT(pDesc->pRootSignature);
        
        Pipeline* pPipeline = (Pipeline*)conf_calloc(1, sizeof(*pPipeline));
        ASSERT(pPipeline);
        
        memcpy(&(pPipeline->mGraphics), pDesc, sizeof(*pDesc));
        pPipeline->mType = PIPELINE_TYPE_GRAPHICS;
        pPipeline->pShader = pPipeline->mGraphics.pShaderProgram;
        pPipeline->pRenderer = pRenderer;
        
        // create metal pipeline descriptor
        MTLRenderPipelineDescriptor *renderPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
        renderPipelineDesc.vertexFunction = pDesc->pShaderProgram->mtlVertexShader;
        renderPipelineDesc.fragmentFunction = pDesc->pShaderProgram->mtlFragmentShader;
        if(pDesc->mRenderTargetCount > 0) renderPipelineDesc.sampleCount = pDesc->ppRenderTargets[0]->pTexture->mDesc.mSampleCount;
        else renderPipelineDesc.sampleCount = pDesc->pDepthStencil->pTexture->mDesc.mSampleCount;
        
        
        // add vertex layout to descriptor
        if (pPipeline->mGraphics.pVertexLayout != nil)
        {
            // setup vertex descriptors
            for(uint i = 0; i < pPipeline->mGraphics.pVertexLayout->mAttribCount; i++)
            {
                const VertexAttrib* attrib = pPipeline->mGraphics.pVertexLayout->mAttribs + i;
                renderPipelineDesc.vertexDescriptor.attributes[i].offset = attrib->mOffset;
                renderPipelineDesc.vertexDescriptor.attributes[i].bufferIndex = attrib->mBinding;
                renderPipelineDesc.vertexDescriptor.attributes[i].format = util_to_mtl_vertex_format(attrib->mFormat);
            }
            renderPipelineDesc.vertexDescriptor.layouts[0].stride = calculateVertexLayoutStride(pPipeline->mGraphics.pVertexLayout);
            renderPipelineDesc.vertexDescriptor.layouts[0].stepRate = 1;
            renderPipelineDesc.vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
        }
        
#if !defined(TARGET_IOS)
        // add pipeline settings to descriptor
        switch (pDesc->mPrimitiveTopo) {
            case PRIMITIVE_TOPO_POINT_LIST: renderPipelineDesc.inputPrimitiveTopology = MTLPrimitiveTopologyClassPoint; break;
            case PRIMITIVE_TOPO_LINE_LIST:  renderPipelineDesc.inputPrimitiveTopology = MTLPrimitiveTopologyClassLine; break;
            case PRIMITIVE_TOPO_LINE_STRIP: renderPipelineDesc.inputPrimitiveTopology = MTLPrimitiveTopologyClassLine; break;
            case PRIMITIVE_TOPO_TRI_LIST:   renderPipelineDesc.inputPrimitiveTopology = MTLPrimitiveTopologyClassTriangle; break;
            case PRIMITIVE_TOPO_TRI_STRIP:  renderPipelineDesc.inputPrimitiveTopology = MTLPrimitiveTopologyClassTriangle; break;
        }
#endif
        
        // assign render target pixel format for all attachments
        const BlendState* blendState = pDesc->pBlendState ? pDesc->pBlendState : pDefaultBlendState;
        for (uint32_t i=0; i<pDesc->mRenderTargetCount; i++)
        {
            renderPipelineDesc.colorAttachments[i].pixelFormat = pDesc->ppRenderTargets[i]->pTexture->mtlPixelFormat;
            
            // set blend state
            bool hasBlendState = (blendState!=nil);
            renderPipelineDesc.colorAttachments[i].blendingEnabled = hasBlendState;
            if (hasBlendState)
            {
                renderPipelineDesc.colorAttachments[i].rgbBlendOperation = blendState->blendStatePerRenderTarget[i].blendMode;
                renderPipelineDesc.colorAttachments[i].alphaBlendOperation = blendState->blendStatePerRenderTarget[i].blendAlphaMode;
                renderPipelineDesc.colorAttachments[i].sourceRGBBlendFactor = blendState->blendStatePerRenderTarget[i].srcFactor;
                renderPipelineDesc.colorAttachments[i].destinationRGBBlendFactor = blendState->blendStatePerRenderTarget[i].destFactor;
                renderPipelineDesc.colorAttachments[i].sourceAlphaBlendFactor = blendState->blendStatePerRenderTarget[i].srcAlphaFactor;
                renderPipelineDesc.colorAttachments[i].destinationAlphaBlendFactor = blendState->blendStatePerRenderTarget[i].destAlphaFactor;
            }
        }
        
        // assign pixel format form depth attachment
        if (pDesc->pDepthStencil !=nil )
        {
            renderPipelineDesc.depthAttachmentPixelFormat = pDesc->pDepthStencil->pTexture->mtlPixelFormat;
        }
        
        // create pipeline from descriptor
        NSError *error = nil;
        pPipeline->mtlRenderPipelineState = [pRenderer->pDevice newRenderPipelineStateWithDescriptor:renderPipelineDesc options:MTLPipelineOptionNone reflection:nil error:&error];
        if (!pPipeline->mtlRenderPipelineState)
        {
            NSLog(@"Failed to create render pipeline state, error %@", error);
            return;
        }
        
        *ppPipeline = pPipeline;
    }
    
    void addComputePipeline(Renderer* pRenderer, const ComputePipelineDesc* pDesc, Pipeline** ppPipeline)
    {
        ASSERT(pRenderer);
        ASSERT(pRenderer->pDevice != nil);
        ASSERT(pDesc);
        ASSERT(pDesc->pShaderProgram);
        ASSERT(pDesc->pRootSignature);
        
        Pipeline* pPipeline = (Pipeline*)conf_calloc(1, sizeof(*pPipeline));
        ASSERT(pPipeline);
        
        memcpy(&(pPipeline->mCompute), pDesc, sizeof(*pDesc));
        pPipeline->mType = PIPELINE_TYPE_COMPUTE;
        pPipeline->pShader = pPipeline->mCompute.pShaderProgram;
        pPipeline->pRenderer = pRenderer;
        
        NSError *error = nil;
        pPipeline->mtlComputePipelineState = [pRenderer->pDevice newComputePipelineStateWithFunction:pDesc->pShaderProgram->mtlComputeShader error:nil];
        if (!pPipeline->mtlComputePipelineState)
        {
            NSLog(@"Failed to create compute pipeline state, error %@", error);
            SAFE_FREE(pPipeline);
            return;
        }
        
        *ppPipeline = pPipeline;
    }
    
    void removePipeline(Renderer* pRenderer, Pipeline* pPipeline)
    {
        ASSERT(pPipeline);
        pPipeline->mtlRenderPipelineState = nil;
        pPipeline->mtlComputePipelineState = nil;
        SAFE_FREE(pPipeline);
    }
    
    void addBlendState(BlendState** ppBlendState,
                       BlendConstant srcFactor, BlendConstant destFactor,
                       BlendConstant srcAlphaFactor, BlendConstant destAlphaFactor,
                       BlendMode blendMode, BlendMode blendAlphaMode,
                       const int mask, const int MRTRenderTargetNumber, const bool alphaToCoverage)
    {
        ASSERT(srcFactor < BlendConstant::MAX_BLEND_CONSTANTS);
        ASSERT(destFactor < BlendConstant::MAX_BLEND_CONSTANTS);
        ASSERT(srcAlphaFactor < BlendConstant::MAX_BLEND_CONSTANTS);
        ASSERT(destAlphaFactor < BlendConstant::MAX_BLEND_CONSTANTS);
        ASSERT(blendMode < BlendMode::MAX_BLEND_MODES);
        ASSERT(blendAlphaMode < BlendMode::MAX_BLEND_MODES);
        
        BlendState blendState = {};
        
        // Go over each RT blend state.
        for(int i = 0; i < MAX_RENDER_TARGET_ATTACHMENTS; ++i)
        {
            if(MRTRenderTargetNumber & (1 << i))
            {
                blendState.blendStatePerRenderTarget[i].srcFactor = gMtlBlendConstantTranslator[srcFactor];
                blendState.blendStatePerRenderTarget[i].destFactor = gMtlBlendConstantTranslator[destFactor];
                blendState.blendStatePerRenderTarget[i].srcAlphaFactor = gMtlBlendConstantTranslator[srcAlphaFactor];
                blendState.blendStatePerRenderTarget[i].destAlphaFactor = gMtlBlendConstantTranslator[destAlphaFactor];
                blendState.blendStatePerRenderTarget[i].blendMode = gMtlBlendOpTranslator[blendMode];
                blendState.blendStatePerRenderTarget[i].blendAlphaMode = gMtlBlendOpTranslator[blendAlphaMode];
            }
        }
        blendState.alphaToCoverage = alphaToCoverage;
        
        *ppBlendState = (BlendState*)conf_malloc(sizeof(blendState));
        memcpy(*ppBlendState, &blendState, sizeof(blendState));
    }
    
    void removeBlendState(BlendState* pBlendState)
    {
        ASSERT(pBlendState);
        SAFE_FREE(pBlendState);
    }
    
    void addDepthState(Renderer* pRenderer, DepthState** ppDepthState, const bool depthTest, const bool depthWrite,
       const CompareMode depthFunc /*= CompareMode::CMP_LEQUAL*/,
       const bool stencilTest /*= false*/,
       const uint8 stencilReadMask /*= 0xFF*/,
       const uint8 stencilWriteMask /*= 0xFF*/,
       const CompareMode stencilFrontFunc /*= CompareMode::CMP_ALWAYS*/,
       const StencilOp stencilFrontFail /*= StencilOp::STENCIL_OP_KEEP*/,
       const StencilOp depthFrontFail /*= StencilOp::STENCIL_OP_KEEP*/,
       const StencilOp stencilFrontPass /*= StencilOp::STENCIL_OP_KEEP*/,
       const CompareMode stencilBackFunc /*= CompareMode::CMP_ALWAYS*/,
       const StencilOp stencilBackFail /*= StencilOp::STENCIL_OP_KEEP*/,
       const StencilOp depthBackFail /*= StencilOp::STENCIL_OP_KEEP*/,
       const StencilOp stencilBackPass /*= StencilOp::STENCIL_OP_KEEP*/)
    {
        ASSERT(depthFunc < CompareMode::MAX_COMPARE_MODES);
        ASSERT(stencilFrontFunc < CompareMode::MAX_COMPARE_MODES);
        ASSERT(stencilFrontFail < StencilOp::MAX_STENCIL_OPS);
        ASSERT(depthFrontFail < StencilOp::MAX_STENCIL_OPS);
        ASSERT(stencilFrontPass < StencilOp::MAX_STENCIL_OPS);
        ASSERT(stencilBackFunc < CompareMode::MAX_COMPARE_MODES);
        ASSERT(stencilBackFail < StencilOp::MAX_STENCIL_OPS);
        ASSERT(depthBackFail < StencilOp::MAX_STENCIL_OPS);
        ASSERT(stencilBackPass < StencilOp::MAX_STENCIL_OPS);
        
        MTLDepthStencilDescriptor* descriptor = [[MTLDepthStencilDescriptor alloc] init];
        descriptor.depthCompareFunction = gMtlComparisonFunctionTranslator[depthFunc];
        descriptor.depthWriteEnabled = depthWrite;
        descriptor.backFaceStencil.stencilCompareFunction = gMtlComparisonFunctionTranslator[stencilBackFunc];
        descriptor.backFaceStencil.depthFailureOperation = gMtlStencilOpTranslator[depthBackFail];
        descriptor.backFaceStencil.stencilFailureOperation = gMtlStencilOpTranslator[stencilBackFail];
        descriptor.backFaceStencil.depthStencilPassOperation = gMtlStencilOpTranslator[stencilBackPass];
        descriptor.backFaceStencil.readMask = stencilReadMask;
        descriptor.backFaceStencil.writeMask = stencilWriteMask;
        descriptor.frontFaceStencil.stencilCompareFunction = gMtlComparisonFunctionTranslator[stencilFrontFunc];
        descriptor.frontFaceStencil.depthFailureOperation = gMtlStencilOpTranslator[depthFrontFail];
        descriptor.frontFaceStencil.stencilFailureOperation = gMtlStencilOpTranslator[stencilFrontFail];
        descriptor.frontFaceStencil.depthStencilPassOperation = gMtlStencilOpTranslator[stencilFrontPass];
        descriptor.frontFaceStencil.readMask = stencilReadMask;
        descriptor.frontFaceStencil.writeMask = stencilWriteMask;
        
        DepthState* pDepthState = (DepthState*)conf_calloc(1, sizeof(*pDepthState));
        pDepthState->mtlDepthState = [pRenderer->pDevice newDepthStencilStateWithDescriptor:descriptor];
        
        *ppDepthState = pDepthState;
    }
    
    void removeDepthState(DepthState* pDepthState)
    {
        ASSERT(pDepthState);
        pDepthState->mtlDepthState = nil;
        SAFE_FREE(pDepthState);
    }
    
    void addRasterizerState(RasterizerState** ppRasterizerState,
        const CullMode cullMode,
        const int depthBias /*= 0*/,
        const float slopeScaledDepthBias /*= 0*/,
        const FillMode fillMode /*= FillMode::FILL_MODE_SOLID*/,
        const bool multiSample /*= false*/,
        const bool scissor /*= false*/)
    {
        ASSERT(fillMode < FillMode::MAX_FILL_MODES);
        ASSERT(cullMode < CullMode::MAX_CULL_MODES);
        
        RasterizerState rasterizerState = {};
        
        rasterizerState.cullMode = MTLCullModeNone;
        if (cullMode == CULL_MODE_BACK)
            rasterizerState.cullMode = MTLCullModeBack;
        else if (cullMode == CULL_MODE_FRONT)
            rasterizerState.cullMode = MTLCullModeFront;
        
        rasterizerState.fillMode = (fillMode == FILL_MODE_SOLID ? MTLTriangleFillModeFill : MTLTriangleFillModeLines);
        rasterizerState.depthBias = depthBias;
        rasterizerState.depthBiasSlopeFactor = slopeScaledDepthBias;
        rasterizerState.scissorEnable = scissor;
        rasterizerState.multisampleEnable = multiSample;
        
        *ppRasterizerState = (RasterizerState*)conf_malloc(sizeof(rasterizerState));
        memcpy(*ppRasterizerState, &rasterizerState, sizeof(rasterizerState));
    }
    
    void removeRasterizerState(RasterizerState* pRasterizerState)
    {
        ASSERT(pRasterizerState);
        SAFE_FREE(pRasterizerState);
    }
    
    // -------------------------------------------------------------------------------------------------
    // Buffer functions
    // -------------------------------------------------------------------------------------------------
    void mapBuffer(Renderer* pRenderer, Buffer* pBuffer, ReadRange* pRange = NULL)
    {
        ASSERT(pBuffer->mDesc.mMemoryUsage != RESOURCE_MEMORY_USAGE_GPU_ONLY && "Trying to map non-cpu accessible resource");
        pBuffer->pCpuMappedAddress = pBuffer->mtlBuffer.contents;
    }
    void unmapBuffer(Renderer* pRenderer, Buffer* pBuffer)
    {
        ASSERT(pBuffer->mDesc.mMemoryUsage != RESOURCE_MEMORY_USAGE_GPU_ONLY && "Trying to unmap non-cpu accessible resource");
        pBuffer->pCpuMappedAddress = nil;
    }
    
    // -------------------------------------------------------------------------------------------------
    // Command buffer functions
    // -------------------------------------------------------------------------------------------------
    
    void beginCmd(Cmd* pCmd){
        @autoreleasepool {
            ASSERT(pCmd);
            pCmd->mtlRenderEncoder = nil;
            pCmd->mtlComputeEncoder = nil;
            pCmd->mtlBlitEncoder = nil;
            pCmd->pShader = nil;
            pCmd->pRenderPassDesc = nil;
            pCmd->selectedIndexBuffer = nil;
            pCmd->pBoundRootSignature = nil;
            pCmd->mtlCommandBuffer = [pCmd->pCmdPool->pQueue->mtlCommandQueue commandBuffer];
        }
    }
    
    void endCmd(Cmd* pCmd)
    {
        // Reset the bound resources flags for the current root signature's descriptor manager.
        if(pCmd->pBoundRootSignature)
        {
            const tinystl::unordered_hash_node<ThreadID, DescriptorManager*>* pNode = pCmd->pBoundRootSignature->pDescriptorManagerMap.find(Thread::GetCurrentThreadID()).node;
            if (pNode) reset_bound_resources(pNode->second);
        }
    }
    
    void cmdBeginRender(Cmd* pCmd, uint32_t renderTargetCount, RenderTarget** ppRenderTargets, RenderTarget* pDepthStencil, const LoadActionsDesc* pLoadActions)
    {
        ASSERT(pCmd);
        ASSERT(ppRenderTargets || pDepthStencil);
        
        @autoreleasepool {
            pCmd->pRenderPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];
            
            // Flush color attachments
            for (uint32_t i=0; i<renderTargetCount; i++)
            {
                Texture* colorAttachment = ppRenderTargets[i]->pTexture;
                
                pCmd->pRenderPassDesc.colorAttachments[i].texture = colorAttachment->mtlTexture;
                pCmd->pRenderPassDesc.colorAttachments[i].loadAction = (pLoadActions!=NULL ? util_to_mtl_load_action(pLoadActions->mLoadActionsColor[i]) : MTLLoadActionLoad);
                pCmd->pRenderPassDesc.colorAttachments[i].storeAction = MTLStoreActionStore;
                if (pLoadActions!=NULL)
                {
                    const ClearValue& clearValue = pLoadActions->mClearColorValues[i];
                    pCmd->pRenderPassDesc.colorAttachments[i].clearColor = MTLClearColorMake(clearValue.r, clearValue.g, clearValue.b, clearValue.a);
                }
            }
            
            if (pDepthStencil != nil)
            {
                pCmd->pRenderPassDesc.depthAttachment.texture = pDepthStencil->pTexture->mtlTexture;
                pCmd->pRenderPassDesc.depthAttachment.loadAction = (pLoadActions!=NULL ? util_to_mtl_load_action(pLoadActions->mLoadActionDepth) : MTLLoadActionLoad);
                pCmd->pRenderPassDesc.depthAttachment.storeAction = MTLStoreActionStore;
                if (pLoadActions!=NULL){
                    pCmd->pRenderPassDesc.depthAttachment.clearDepth = pLoadActions->mClearDepth.depth;
                }
            }
            
            bool switchedEncoders = util_sync_encoders(pCmd, CMD_POOL_DIRECT); // Check if we need to sync different types of encoders (only on direct cmds).
            util_end_current_encoders(pCmd);
            pCmd->mtlRenderEncoder = [pCmd->mtlCommandBuffer renderCommandEncoderWithDescriptor:pCmd->pRenderPassDesc];
            if(switchedEncoders) [pCmd->mtlRenderEncoder waitForFence:pCmd->mtlEncoderFence beforeStages:MTLRenderStageVertex];
            
            [pCmd->mtlRenderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        }
    }
    
    void cmdEndRender(Cmd* pCmd, uint32_t renderTargetCount, RenderTarget** ppRenderTargets, RenderTarget* pDepthStencil)
    {
        ASSERT(pCmd);
        
        // Reset the bound resources flags for the current root signature's descriptor manager.
        const tinystl::unordered_hash_node<ThreadID, DescriptorManager*>* pNode = pCmd->pBoundRootSignature->pDescriptorManagerMap.find(Thread::GetCurrentThreadID()).node;
        if (pNode) reset_bound_resources(pNode->second);

        @autoreleasepool {
            util_end_current_encoders(pCmd);
        }
    }
    
    void cmdSetViewport(Cmd* pCmd, float x, float y, float width, float height, float minDepth, float maxDepth)
    {
        ASSERT(pCmd);
        // TODO: Add more error messages like these in other cmd functions.
        if (pCmd->mtlRenderEncoder==nil)
        {
            LOGERROR("Using cmdSetViewport out of a cmdBeginRender / cmdEndRender block is not allowed");
            return;
        }
        
        MTLViewport viewport;
        viewport.originX = x;
        viewport.originY = y;
        viewport.width = width;
        viewport.height = height;
        viewport.znear = minDepth;
        viewport.zfar = maxDepth;
        
        [pCmd->mtlRenderEncoder setViewport:viewport];
    }
    
    void cmdSetScissor(Cmd* pCmd, uint32_t x, uint32_t y, uint32_t width, uint32_t height)
    {
        ASSERT(pCmd);
        if (pCmd->mtlRenderEncoder==nil)
        {
            LOGERROR("Using cmdSetScissor out of a cmdBeginRender / cmdEndRender block is not allowed");
            return;
        }
        
        // Get the maximum safe scissor values for the current render pass.
        uint32_t maxScissorX = pCmd->pRenderPassDesc.colorAttachments[0].texture.width > 0 ? pCmd->pRenderPassDesc.colorAttachments[0].texture.width : pCmd->pRenderPassDesc.depthAttachment.texture.width;
        uint32_t maxScissorY = pCmd->pRenderPassDesc.colorAttachments[0].texture.height > 0 ? pCmd->pRenderPassDesc.colorAttachments[0].texture.height : pCmd->pRenderPassDesc.depthAttachment.texture.height;
        uint32_t maxScissorW = maxScissorX - int32_t(max(x, 0));
        uint32_t maxScissorH = maxScissorY - int32_t(max(y, 0));
        
        // Make sure neither width or height are 0 (unsupported by Metal).
        if(width == 0u) width = 1u;
        if(height == 0u) height = 1u;
        
        MTLScissorRect scissor;
        scissor.x = min(x, maxScissorX);
        scissor.y = min(y, maxScissorY);
        scissor.width = min(width, maxScissorW);
        scissor.height = min(height, maxScissorH);
        
        [pCmd->mtlRenderEncoder setScissorRect:scissor];
    }
    
   void cmdBindPipeline(Cmd* pCmd, Pipeline* pPipeline)
    {
        ASSERT(pCmd);
        ASSERT(pPipeline);
        
        pCmd->pShader = pPipeline->pShader;
        
        @autoreleasepool {
            if (pPipeline->mType == PIPELINE_TYPE_GRAPHICS)
            {
                [pCmd->mtlRenderEncoder setRenderPipelineState:pPipeline->mtlRenderPipelineState];
                
                RasterizerState* rasterizerState = pPipeline->mGraphics.pRasterizerState ? pPipeline->mGraphics.pRasterizerState : pDefaultRasterizerState;
                [pCmd->mtlRenderEncoder setCullMode:rasterizerState->cullMode];
                
                if(pCmd->pRenderPassDesc.depthAttachment.texture != nil) {
                    DepthState* depthState = pPipeline->mGraphics.pDepthState ? pPipeline->mGraphics.pDepthState : pDefaultDepthState;
                    [pCmd->mtlRenderEncoder setDepthStencilState:depthState->mtlDepthState];
                }
                
                switch (pPipeline->mGraphics.mPrimitiveTopo) {
                    case PRIMITIVE_TOPO_POINT_LIST: pCmd->selectedPrimitiveType = MTLPrimitiveTypePoint; break;
                    case PRIMITIVE_TOPO_LINE_LIST: pCmd->selectedPrimitiveType = MTLPrimitiveTypeLine; break;
                    case PRIMITIVE_TOPO_LINE_STRIP: pCmd->selectedPrimitiveType = MTLPrimitiveTypeLineStrip; break;
                    case PRIMITIVE_TOPO_TRI_LIST: pCmd->selectedPrimitiveType = MTLPrimitiveTypeTriangle; break;
                    case PRIMITIVE_TOPO_TRI_STRIP: pCmd->selectedPrimitiveType = MTLPrimitiveTypeTriangleStrip; break;
                }
            }
            else
            {
                if(!pCmd->mtlComputeEncoder)
                {
                    util_end_current_encoders(pCmd);
                    pCmd->mtlComputeEncoder = [pCmd->mtlCommandBuffer computeCommandEncoder];
                }
                [pCmd->mtlComputeEncoder setComputePipelineState:pPipeline->mtlComputePipelineState];
            }
        }
    }
    
    void cmdBindIndexBuffer(Cmd* pCmd, Buffer* pBuffer)
    {
        ASSERT(pCmd);
        ASSERT(pBuffer);
        
        pCmd->selectedIndexBuffer = pBuffer;
    }
    
    void cmdBindVertexBuffer(Cmd* pCmd, uint32_t bufferCount, Buffer** ppBuffers)
    {
        ASSERT(pCmd);
        ASSERT(0 != bufferCount);
        ASSERT(ppBuffers);
        
        for (uint32_t i=0; i<bufferCount; i++)
        {
            [pCmd->mtlRenderEncoder setVertexBuffer:ppBuffers[i]->mtlBuffer offset:ppBuffers[i]->mPositionInHeap atIndex:i];
        }
    }
    
    void cmdDraw(Cmd* pCmd, uint32_t vertexCount, uint32_t firstVertex)
    {
        ASSERT(pCmd);
        [pCmd->mtlRenderEncoder drawPrimitives:pCmd->selectedPrimitiveType
                                    vertexStart:firstVertex
                                    vertexCount:vertexCount];
    }
    
    void cmdDrawInstanced(Cmd* pCmd, uint32_t vertexCount, uint32_t firstVertex, uint32_t instanceCount)
    {
        ASSERT(pCmd);
        [pCmd->mtlRenderEncoder drawPrimitives:pCmd->selectedPrimitiveType
                                    vertexStart:firstVertex
                                    vertexCount:vertexCount
                                  instanceCount:instanceCount];
    }
    
    void cmdDrawIndexed(Cmd* pCmd, uint32_t indexCount, uint32_t firstIndex)
    {
        ASSERT(pCmd);
        
        Buffer* indexBuffer = pCmd->selectedIndexBuffer;
        MTLIndexType indexType = (indexBuffer->mDesc.mIndexType == INDEX_TYPE_UINT16 ? MTLIndexTypeUInt16 : MTLIndexTypeUInt32);
        uint64_t offset = firstIndex * (indexBuffer->mDesc.mIndexType == INDEX_TYPE_UINT16 ? 2 : 4);
        
        [pCmd->mtlRenderEncoder drawIndexedPrimitives:pCmd->selectedPrimitiveType
                                            indexCount:indexCount
                                             indexType:indexType
                                           indexBuffer:indexBuffer->mtlBuffer
                                     indexBufferOffset:offset];
    }
    
    void cmdDrawIndexedInstanced(Cmd* pCmd, uint32_t indexCount, uint32_t firstIndex, uint32_t instanceCount)
    {
        ASSERT(pCmd);
        
        Buffer* indexBuffer = pCmd->selectedIndexBuffer;
        MTLIndexType indexType = (indexBuffer->mDesc.mIndexType == INDEX_TYPE_UINT16 ? MTLIndexTypeUInt16 : MTLIndexTypeUInt32);
        uint64_t offset = firstIndex * (indexBuffer->mDesc.mIndexType == INDEX_TYPE_UINT16 ? 2 : 4);
        
        [pCmd->mtlRenderEncoder drawIndexedPrimitives:pCmd->selectedPrimitiveType
                                            indexCount:indexCount
                                             indexType:indexType
                                           indexBuffer:indexBuffer->mtlBuffer
                                     indexBufferOffset:offset
                                         instanceCount:instanceCount];
    }
    
    void cmdDispatch(Cmd* pCmd, uint32_t groupCountX, uint32_t groupCountY, uint32_t groupCountZ)
    {
        ASSERT(pCmd);
        ASSERT(pCmd->mtlComputeEncoder != nil);
        
        Shader* shader = pCmd->pShader;
        
        MTLSize threadsPerThreadgroup = MTLSizeMake(shader->mNumThreadsPerGroup[0], shader->mNumThreadsPerGroup[1], shader->mNumThreadsPerGroup[2]);
        MTLSize threadgroupCount = MTLSizeMake(groupCountX, groupCountY, groupCountZ);
        
        [pCmd->mtlComputeEncoder dispatchThreadgroups:threadgroupCount threadsPerThreadgroup:threadsPerThreadgroup];
    }
    
    void cmdResourceBarrier(Cmd* pCmd, uint32_t numBufferBarriers, BufferBarrier* pBufferBarriers, uint32_t numTextureBarriers, TextureBarrier* pTextureBarriers, bool batch)
    {
    }
    
    void cmdSynchronizeResources(Cmd* pCmd, uint32_t numBuffers, Buffer** ppBuffers, uint32_t numTextures, Texture** ppTextures, bool batch)
    {
    }
    
    void cmdFlushBarriers(Cmd* pCmd)
    {
        
    }
    
    void cmdUpdateBuffer(Cmd* pCmd, uint64_t srcOffset, uint64_t dstOffset, uint64_t size, Buffer* pSrcBuffer, Buffer* pBuffer)
    {
        ASSERT(pCmd);
        ASSERT(pSrcBuffer);
        ASSERT(pSrcBuffer->mtlBuffer);
        ASSERT(pBuffer);
        ASSERT(pBuffer->mtlBuffer);
        ASSERT(srcOffset + size <= pSrcBuffer->mDesc.mSize);
        ASSERT(dstOffset + size <= pBuffer->mDesc.mSize);

        util_end_current_encoders(pCmd);
        pCmd->mtlBlitEncoder = [pCmd->mtlCommandBuffer blitCommandEncoder];
        
        [pCmd->mtlBlitEncoder copyFromBuffer:pSrcBuffer->mtlBuffer
                                 sourceOffset:srcOffset
                                     toBuffer:pBuffer->mtlBuffer
                            destinationOffset:dstOffset
                                         size:size];
    }
    
    void cmdUpdateSubresources(Cmd* pCmd, uint32_t startSubresource, uint32_t numSubresources, SubresourceDataDesc* pSubresources, Buffer* pIntermediate, uint64_t intermediateOffset, Texture* pTexture)
    {
        util_end_current_encoders(pCmd);
        pCmd->mtlBlitEncoder = [pCmd->mtlCommandBuffer blitCommandEncoder];
        
        uint nLayers = pTexture->mDesc.mArraySize;
        uint nFaces = pTexture->mDesc.mType == TEXTURE_TYPE_CUBE ? 6 : 1;
        uint nMips = pTexture->mDesc.mMipLevels;
        
        uint32_t subresourceOffset = 0;
        for (uint32_t layer = 0; layer < nLayers; ++layer)
        {
            for (uint32_t face = 0; face < nFaces; ++face)
            {
                for (uint32_t mip = 0; mip < nMips; ++mip)
                {
                    SubresourceDataDesc* pRes = &pSubresources[(layer * nFaces * nMips) + (face * nMips) + mip];
                    uint32_t mipmapWidth = max(pTexture->mDesc.mWidth >> mip, 1);
                    uint32_t mipmapHeight = max(pTexture->mDesc.mHeight >> mip, 1);
                    
                    // Copy the data for this resource to an intermediate buffer.
                    memcpy((uint8_t*)pIntermediate->pCpuMappedAddress + intermediateOffset + subresourceOffset, pRes->pData, pRes->mSlicePitch);
                    
                    // Copy to the texture's final subresource.
                    [pCmd->mtlBlitEncoder copyFromBuffer:pIntermediate->mtlBuffer
                                            sourceOffset:intermediateOffset + subresourceOffset
                                       sourceBytesPerRow:pRes->mRowPitch
                                     sourceBytesPerImage:pRes->mSlicePitch
                                              sourceSize:MTLSizeMake(mipmapWidth, mipmapHeight, 1)
                                               toTexture:pTexture->mtlTexture
                                        destinationSlice:layer * nFaces + face
                                        destinationLevel:mip
                                       destinationOrigin:MTLOriginMake(0, 0, 0)];
                    
                    // Increase the subresource offset.
                    subresourceOffset += pRes->mSlicePitch;
                }
            }
        }
    }
    
    void cmdCopyBufferToTexture2d(Cmd* pCmd, uint32_t width, uint32_t height, uint32_t rowPitch, uint64_t bufferOffset, uint32_t mipLevel, Buffer* pBuffer, Texture* pTexture)
    {
        ASSERT(pCmd);
        ASSERT(pBuffer);
        ASSERT(pTexture);
        ASSERT(pCmd->mtlCommandBuffer);
        
        util_end_current_encoders(pCmd);
        pCmd->mtlBlitEncoder = [pCmd->mtlCommandBuffer blitCommandEncoder];
        
        width = max<uint32_t>(width, 1);
        height = max<uint32_t>(height, 1);
        
        [pCmd->mtlBlitEncoder copyFromBuffer:pBuffer->mtlBuffer
                                sourceOffset:bufferOffset
                           sourceBytesPerRow: pTexture->mIsCompressed ? rowPitch*4 : rowPitch  //TODO: must ask Apple why we have to *4 here. Otherwise a validation error is thrown: metal bug?
                         sourceBytesPerImage:0     // this is only needed for 3D textures and texture arrays
                                  sourceSize:MTLSizeMake(width, height, 1)
                                   toTexture:pTexture->mtlTexture
                            destinationSlice:0
                            destinationLevel:mipLevel
                           destinationOrigin:MTLOriginMake(0, 0, 0)];
    }
    
    void acquireNextImage(Renderer* pRenderer, SwapChain* pSwapChain, Semaphore* pSignalSemaphore, Fence* pFence, uint32_t* pImageIndex)
    {
        ASSERT(pRenderer);
        ASSERT(pRenderer->pDevice != nil);
        ASSERT(pSwapChain);
        ASSERT(pSignalSemaphore || pFence);
        
#ifdef TARGET_IOS
        *pImageIndex = (uint32_t)(pSwapChain->pMTKView.currentDrawable.drawableID);
        return;
#else
        id<CAMetalDrawable> drawable = pSwapChain->pMTKView.currentDrawable;
        id<MTLTexture> mtlTexture = drawable.texture;
        
        // Look for the render target containing this texture.
        // If not found: assign it to an empty slot
        for (uint32_t i=0; i<pSwapChain->mDesc.mImageCount; i++)
        {
            RenderTarget* renderTarget = pSwapChain->ppSwapchainRenderTargets[i];
            if (renderTarget->pTexture->mtlTexture == mtlTexture)
            {
                *pImageIndex = i;
                return;
            }
        }
        
        // Not found: assign the texture to an empty slot
        for (uint32_t i=0; i<pSwapChain->mDesc.mImageCount; i++)
        {
            RenderTarget* renderTarget = pSwapChain->ppSwapchainRenderTargets[i];
            if (renderTarget->pTexture->mtlTexture == nil)
            {
                renderTarget->pTexture->mtlTexture = drawable.texture;
                
                // Update the swapchain RT size according to the new drawable's size.
                renderTarget->pTexture->mDesc.mWidth = (uint32_t)drawable.texture.width;
                renderTarget->pTexture->mDesc.mHeight = (uint32_t)drawable.texture.height;
                pSwapChain->ppSwapchainRenderTargets[i]->mDesc.mWidth = renderTarget->pTexture->mDesc.mWidth;
                pSwapChain->ppSwapchainRenderTargets[i]->mDesc.mHeight = renderTarget->pTexture->mDesc.mHeight;
                
                *pImageIndex = i;
                return;
            }
        }
        
        // The swapchain textures have changed internally:
        // Invalidate the texures and re-acquire the render targets
        for (uint32_t i=0; i<pSwapChain->mDesc.mImageCount; i++)
        {
            pSwapChain->ppSwapchainRenderTargets[i]->pTexture->mtlTexture = nil;
        }
        acquireNextImage(pRenderer, pSwapChain, pSignalSemaphore, pFence, pImageIndex);
#endif
    }
    
    void queueSubmit(Queue* pQueue,uint32_t cmdCount, Cmd** ppCmds, Fence* pFence, uint32_t waitSemaphoreCount, Semaphore** ppWaitSemaphores, uint32_t signalSemaphoreCount, Semaphore** ppSignalSemaphores)
    {
        ASSERT(pQueue);
        ASSERT(cmdCount > 0);
        ASSERT(ppCmds);
        if (waitSemaphoreCount > 0) {
            ASSERT(ppWaitSemaphores);
        }
        if (signalSemaphoreCount > 0) {
            ASSERT(ppSignalSemaphores);
        }
        
        // set the queue built-in semaphore to signal when all command lists finished their execution
        __block uint32_t commandsFinished = 0;
        __block dispatch_semaphore_t blockSemaphore = pQueue->pMtlSemaphore;
        __block dispatch_semaphore_t completedFence = nil;
        if(pFence)
        {
            completedFence = pFence->pMtlSemaphore;
            pFence->mSubmitted = true;
        }
        for (uint32_t i=0; i<cmdCount; i++)
        {
            [ppCmds[i]->mtlCommandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
                commandsFinished++;
                if (commandsFinished == cmdCount){
                    dispatch_semaphore_signal(blockSemaphore);
                    if (completedFence) dispatch_semaphore_signal(completedFence);
                }
            }];
        }
        
        // commit the command lists
        for (uint32_t i=0; i<cmdCount; i++)
        {
            // register the following semaphores for signaling after the work has been done
            for (uint32_t j=0; j<signalSemaphoreCount; j++)
            {
                __block dispatch_semaphore_t blockSemaphore = ppSignalSemaphores[j]->pMtlSemaphore;
                [ppCmds[i]->mtlCommandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
                    dispatch_semaphore_signal(blockSemaphore);
                }];
            }
            
            // Commit any uncommited encoder. This is necessary before committing the command buffer
            util_end_current_encoders(ppCmds[i]);
            [ppCmds[i]->mtlCommandBuffer commit];
        }
    }
    
    void queuePresent(Queue* pQueue, SwapChain* pSwapChain, uint32_t swapChainImageIndex, uint32_t waitSemaphoreCount, Semaphore** ppWaitSemaphores)
    {
        ASSERT(pQueue);
        if (waitSemaphoreCount > 0) {
            ASSERT(ppWaitSemaphores);
        }
        ASSERT(pQueue->mtlCommandQueue != nil);
        
        [pSwapChain->presentCommandBuffer presentDrawable:pSwapChain->pMTKView.currentDrawable];
        
        for (uint32_t i=0; i<waitSemaphoreCount; i++)
        {
            dispatch_semaphore_wait(ppWaitSemaphores[i]->pMtlSemaphore, DISPATCH_TIME_FOREVER);
        }
        
        [pSwapChain->presentCommandBuffer commit];
        
        // after committing a command buffer no more commands can be encoded on it: create a new command buffer for future commands
        pSwapChain->presentCommandBuffer = [pSwapChain->presentCommandQueue commandBuffer];
    }
    
    void waitForFences(Queue* pQueue, uint32_t fenceCount, Fence** ppFences)
    {
        ASSERT(pQueue);
        ASSERT(fenceCount);
        ASSERT(ppFences);
        
        for (uint32_t i=0; i<fenceCount; i++)
        {
            if (ppFences[i]->mSubmitted){
                dispatch_semaphore_wait(ppFences[i]->pMtlSemaphore, DISPATCH_TIME_FOREVER);
                ppFences[i]->mCompleted = true;
            }
            ppFences[i]->mSubmitted = false;
        }
    }
    
    void getFenceStatus(Fence* pFence, FenceStatus* pFenceStatus)
    {
        ASSERT(pFence);
        *pFenceStatus = (pFence->mCompleted ? FENCE_STATUS_COMPLETE : FENCE_STATUS_INCOMPLETE);
    }
    
    void getRawTextureHandle(Renderer* pRenderer, Texture* pTexture, void** ppHandle)
    {
        ASSERT(pRenderer);
        ASSERT(pTexture);
        ASSERT(ppHandle);
        
        *ppHandle = (void*)CFBridgingRetain(pTexture->mtlTexture);
    }
    
    // -------------------------------------------------------------------------------------------------
    // Utility functions
    // -------------------------------------------------------------------------------------------------
    
    bool isImageFormatSupported(ImageFormat::Enum format)
    {
        bool result = false;
        switch (format) {
                // 1 channel
            case ImageFormat::R8: result = true; break;
            case ImageFormat::R16: result = true; break;
            case ImageFormat::R16F: result = true; break;
            case ImageFormat::R32UI: result = true; break;
            case ImageFormat::R32F: result = true; break;
                // 2 channel
            case ImageFormat::RG8: result = true; break;
            case ImageFormat::RG16: result = true; break;
            case ImageFormat::RG16F: result = true; break;
            case ImageFormat::RG32UI: result = true; break;
            case ImageFormat::RG32F: result = true; break;
                // 3 channel
            case ImageFormat::RGB8: result = true; break;
            case ImageFormat::RGB16: result = true; break;
            case ImageFormat::RGB16F: result = true; break;
            case ImageFormat::RGB32UI: result = true; break;
            case ImageFormat::RGB32F: result = true; break;
                // 4 channel
            case ImageFormat::BGRA8: result = true; break;
            case ImageFormat::RGBA16: result = true; break;
            case ImageFormat::RGBA16F: result = true; break;
            case ImageFormat::RGBA32UI: result = true; break;
            case ImageFormat::RGBA32F: result = true; break;
        }
        return result;
    }
    
    uint32_t calculateVertexLayoutStride(const VertexLayout* pVertexLayout)
    {
        ASSERT(pVertexLayout);
        
        uint32_t result = 0;
        for (uint32_t i = 0; i < pVertexLayout->mAttribCount; ++i) {
            result += calculateImageFormatStride(pVertexLayout->mAttribs[i].mFormat);
        }
        return result;
    }
    
    // -------------------------------------------------------------------------------------------------
    // Internal utility functions
    // -------------------------------------------------------------------------------------------------
    
    uint64_t util_pthread_to_uint64(const pthread_t& value)
    {
        uint64_t threadId = 0;
        memcpy(&threadId, &value, sizeof(value));
        return threadId;
    }
    
    MTLPixelFormat util_to_mtl_pixel_format(const ImageFormat::Enum &format, const bool &srgb)
    {
        MTLPixelFormat result = MTLPixelFormatInvalid;
        
        if (format >= sizeof(gMtlFormatTranslator) / sizeof(gMtlFormatTranslator[0]))
        {
            LOGERROR("Failed to Map from ConfettilFileFromat to MTLPixelFormat, should add map method in gMtlFormatTranslator");
        }
        else
        {
            result = gMtlFormatTranslator[format];
            if (srgb)
            {
                if(result == MTLPixelFormatRGBA8Unorm) result = MTLPixelFormatRGBA8Unorm_sRGB;
                else if(result == MTLPixelFormatBGRA8Unorm) result = MTLPixelFormatBGRA8Unorm_sRGB;
#ifndef TARGET_IOS
                else if(result == MTLPixelFormatBC1_RGBA) result = MTLPixelFormatBC1_RGBA_sRGB;
                else if(result == MTLPixelFormatBC2_RGBA) result = MTLPixelFormatBC2_RGBA_sRGB;
                else if(result == MTLPixelFormatBC3_RGBA) result = MTLPixelFormatBC3_RGBA_sRGB;
                else if(result == MTLPixelFormatBC7_RGBAUnorm) result = MTLPixelFormatBC7_RGBAUnorm_sRGB;
#endif
            }
        }
        
        return result;
    }
    
    bool util_is_mtl_depth_pixel_format(const MTLPixelFormat &format)
    {
        return format == MTLPixelFormatDepth32Float ||
        format == MTLPixelFormatDepth32Float_Stencil8
#ifndef TARGET_IOS
        || format == MTLPixelFormatDepth16Unorm
        || format == MTLPixelFormatDepth24Unorm_Stencil8
#endif
        ;
    }
    
    bool util_is_mtl_compressed_pixel_format(const MTLPixelFormat &format)
    {
#ifndef TARGET_IOS
        return format == MTLPixelFormatBC1_RGBA ||
        format == MTLPixelFormatBC1_RGBA_sRGB ||
        format == MTLPixelFormatBC2_RGBA ||
        format == MTLPixelFormatBC2_RGBA_sRGB ||
        format == MTLPixelFormatBC3_RGBA ||
        format== MTLPixelFormatBC4_RUnorm ||
        format == MTLPixelFormatBC4_RSnorm ||
        format == MTLPixelFormatBC5_RGUnorm ||
        format == MTLPixelFormatBC5_RGSnorm ||
        format == MTLPixelFormatBC6H_RGBFloat ||
        format == MTLPixelFormatBC6H_RGBUfloat ||
        format == MTLPixelFormatBC7_RGBAUnorm ||
        format == MTLPixelFormatBC7_RGBAUnorm_sRGB;
#else
        return false; // Note: BC texture formats are not supported on iOS.
#endif
    }
    
    MTLVertexFormat util_to_mtl_vertex_format(const ImageFormat::Enum &format)
    {
        switch (format) {
            case ImageFormat::RG8:      return MTLVertexFormatUChar2;
            case ImageFormat::RGB8:     return MTLVertexFormatUChar3;
            case ImageFormat::RGBA8:    return MTLVertexFormatUChar4;
                
            case ImageFormat::RG8S:     return MTLVertexFormatChar2;
            case ImageFormat::RGB8S:    return MTLVertexFormatChar3;
            case ImageFormat::RGBA8S:   return MTLVertexFormatChar4;
                
            case ImageFormat::RG16:     return MTLVertexFormatUShort2Normalized;
            case ImageFormat::RGB16:    return MTLVertexFormatUShort3Normalized;
            case ImageFormat::RGBA16:   return MTLVertexFormatUShort4Normalized;
                
            case ImageFormat::RG16S:    return MTLVertexFormatShort2Normalized;
            case ImageFormat::RGB16S:   return MTLVertexFormatShort3Normalized;
            case ImageFormat::RGBA16S:  return MTLVertexFormatShort4Normalized;
                
            case ImageFormat::RG16I:    return MTLVertexFormatShort2;
            case ImageFormat::RGB16I:   return MTLVertexFormatShort3;
            case ImageFormat::RGBA16I:  return MTLVertexFormatShort4;
                
            case ImageFormat::RG16UI:    return MTLVertexFormatUShort2;
            case ImageFormat::RGB16UI:   return MTLVertexFormatUShort3;
            case ImageFormat::RGBA16UI:  return MTLVertexFormatUShort4;
                
            case ImageFormat::RG16F:    return MTLVertexFormatHalf2;
            case ImageFormat::RGB16F:   return MTLVertexFormatHalf3;
            case ImageFormat::RGBA16F:  return MTLVertexFormatHalf4;
                
            case ImageFormat::R32F:     return MTLVertexFormatFloat;
            case ImageFormat::RG32F:    return MTLVertexFormatFloat2;
            case ImageFormat::RGB32F:   return MTLVertexFormatFloat3;
            case ImageFormat::RGBA32F:  return MTLVertexFormatFloat4;
                
            case ImageFormat::R32I:     return MTLVertexFormatInt;
            case ImageFormat::RG32I:    return MTLVertexFormatInt2;
            case ImageFormat::RGB32I:   return MTLVertexFormatInt3;
            case ImageFormat::RGBA32I:  return MTLVertexFormatInt4;
                
            case ImageFormat::R32UI:    return MTLVertexFormatUInt;
            case ImageFormat::RG32UI:   return MTLVertexFormatUInt2;
            case ImageFormat::RGB32UI:  return MTLVertexFormatUInt3;
            case ImageFormat::RGBA32UI: return MTLVertexFormatUInt4;
                
            case ImageFormat::RGB10A2:  return MTLVertexFormatUInt1010102Normalized;
            default: break;
        }
        NSLog(@"Unknown vertex format: %d", format);
        return MTLVertexFormatInvalid;
    }
    
    MTLLoadAction util_to_mtl_load_action(const LoadActionType &loadActionType)
    {
        if (loadActionType == LOAD_ACTION_DONTCARE)
            return MTLLoadActionDontCare;
        else if (loadActionType == LOAD_ACTION_LOAD)
            return MTLLoadActionLoad;
        else
            return MTLLoadActionClear;
    }
    
    void util_adjust_buffer_slots(const char* srcCode, char* outString)
    {
        const char* srcPtr = srcCode;
        char* dstPtr = outString;
        
        const char* srcLoc = nullptr;
        while((srcLoc = strstr(srcPtr, "buffer(")))
        {
            uint32_t bytesToCopy = (uint32_t)(srcLoc - srcPtr);
            strncpy(dstPtr, srcPtr, bytesToCopy);
            dstPtr += bytesToCopy;
            srcPtr = strchr(srcLoc,')')+1;
            
            int bufferSlotIdx = 0;
            int num = sscanf(srcLoc, "buffer(%d)", &bufferSlotIdx);
            if (num!=1)
            {
                NSLog(@"Malformed shader code: ')' not found for: %s", srcLoc);
                assert(0);
                return;
            }
            bufferSlotIdx = MAX_BUFFER_BINDINGS - bufferSlotIdx - 1;
            sprintf(dstPtr, "buffer(%d)", bufferSlotIdx);
            dstPtr = strchr(dstPtr, ')')+1;
        }
        
        srcLoc = strchr(srcPtr,'\0'); //copy the remaining of the file till the end
        uint32_t bytesToCopy = (uint32_t)(srcLoc - srcPtr);
        strncpy(dstPtr, srcPtr, bytesToCopy);
    }
    
    void util_bind_root_constant(Cmd* pCmd, DescriptorManager* pManager, const DescriptorInfo* descInfo, const DescriptorData* descData)
    {
        // Since root constants are not supported on Metal,
        // we just simulate them binding them as a regular buffer
        uint32_t hash = tinystl::hash(descData->pName);
        
        // Look for the root constant buffer (or create one if needed).
        Buffer* rootConstantBuffer = nil;
        {
            MutexLock mutexLock(rootConstantMutex);
            
            tinystl::unordered_map<uint32_t, tinystl::vector<Buffer*>>::iterator jt = pManager->mRootConstantBuffers.find(hash);
            if (jt.node == nil || jt->second.getCount() <= pManager->mRootConstantBindingCountMap[tinystl::hash(descData->pName)])
            {
                BufferDesc bufferDesc = {};
                bufferDesc.mUsage = BUFFER_USAGE_UPLOAD;
                bufferDesc.mSize = descInfo->mDesc.size;
                bufferDesc.mMemoryUsage = RESOURCE_MEMORY_USAGE_CPU_TO_GPU;
                bufferDesc.mFlags = BUFFER_CREATION_FLAG_OWN_MEMORY_BIT | BUFFER_CREATION_FLAG_PERSISTENT_MAP_BIT;
                
                addBuffer(pCmd->pCmdPool->pRenderer, &bufferDesc, &rootConstantBuffer);
                pManager->mRootConstantBuffers[hash].push_back(rootConstantBuffer);
            }
            else
                rootConstantBuffer = jt->second[pManager->mRootConstantBindingCountMap[tinystl::hash(descData->pName)]];
        }
        
        // Update the data on the buffer.
        memcpy(rootConstantBuffer->pCpuMappedAddress, descData->pRootConstant, descInfo->mDesc.size);
        
        //Bind the buffer to the appropiate pipeline stages.
        if ((descInfo->mDesc.used_stages & SHADER_STAGE_VERT) != 0)
            [pCmd->mtlRenderEncoder setVertexBuffer:rootConstantBuffer->mtlBuffer offset:(rootConstantBuffer->mPositionInHeap + descData->mOffset) atIndex:descInfo->mDesc.reg];
        if ((descInfo->mDesc.used_stages & SHADER_STAGE_FRAG) != 0)
            [pCmd->mtlRenderEncoder setFragmentBuffer:rootConstantBuffer->mtlBuffer offset:(rootConstantBuffer->mPositionInHeap + descData->mOffset) atIndex:descInfo->mDesc.reg];
        if ((descInfo->mDesc.used_stages & SHADER_STAGE_COMP) != 0)
            [pCmd->mtlComputeEncoder setBuffer:rootConstantBuffer->mtlBuffer offset:(rootConstantBuffer->mPositionInHeap + descData->mOffset) atIndex:descInfo->mDesc.reg];
    }
    
    void util_bind_argument_buffer(Cmd* pCmd, DescriptorManager* pManager, const DescriptorInfo* descInfo, const DescriptorData* descData)
    {
        // Look for the argument buffer (or create one if needed).
        uint32_t hash = tinystl::hash(descData->pName);
        Buffer* argumentBuffer;
        id<MTLArgumentEncoder> argumentEncoder = nil;
        id<MTLFunction> shaderStage = nil;
        {
            MutexLock mutexLock(argumentBufferMutex);
            tinystl::unordered_map<uint32_t, Buffer*>::iterator jt = pManager->mArgumentBuffers.find(hash);
            // If not previous argument buffer was found, create a new bufffer.
            if (jt.node == nil)
            {
                // Find a shader stage using this argument buffer.
                ShaderStage stageMask = descInfo->mDesc.used_stages;
                if ((stageMask & SHADER_STAGE_VERT) != 0)   shaderStage = pCmd->pShader->mtlVertexShader;
                else if ((stageMask & SHADER_STAGE_FRAG) != 0)   shaderStage = pCmd->pShader->mtlFragmentShader;
                else if ((stageMask & SHADER_STAGE_COMP) != 0)   shaderStage = pCmd->pShader->mtlComputeShader;
                assert(shaderStage!=nil);
                
                // Create the argument buffer/encoder pair.
                argumentEncoder = [shaderStage newArgumentEncoderWithBufferIndex:descInfo->mDesc.reg];
                BufferDesc bufferDesc = {};
                bufferDesc.mSize = argumentEncoder.encodedLength;
                bufferDesc.mMemoryUsage = RESOURCE_MEMORY_USAGE_CPU_TO_GPU;
                bufferDesc.mFlags = BUFFER_CREATION_FLAG_OWN_MEMORY_BIT;
                addBuffer(pCmd->pCmdPool->pRenderer, &bufferDesc, &argumentBuffer);
                pManager->mArgumentBuffers[hash] = argumentBuffer;
            }
            else
                argumentBuffer = jt->second;
        }
        
        if(!argumentEncoder) argumentEncoder = [shaderStage newArgumentEncoderWithBufferIndex:descInfo->mDesc.reg];
        
        // Update the argument buffer's data.
        // Note: Encoding textures into an argument buffer every frame seems to be crashing the app when trying to do a GPU capture.
        [argumentEncoder setArgumentBuffer:argumentBuffer->mtlBuffer offset:0];
        for (uint32_t i = 0; i < descData->mCount; i++)
        {
            switch(descInfo->mDesc.mtlArgumentBufferType)
            {
                case DESCRIPTOR_TYPE_SAMPLER:
                    [argumentEncoder setSamplerState:descData->ppSamplers[i]->mtlSamplerState atIndex:i];
                    break;
                case DESCRIPTOR_TYPE_BUFFER:
                    [argumentEncoder setBuffer:descData->ppBuffers[i]->mtlBuffer offset:descData->ppBuffers[i]->mPositionInHeap atIndex:i];
                    break;
                case DESCRIPTOR_TYPE_TEXTURE:
                    [argumentEncoder setTexture:descData->ppTextures[i]->mtlTexture atIndex:i];
                    break;
            }
        }
        
        // Bind the argument buffer.
        if ((descInfo->mDesc.used_stages & SHADER_STAGE_VERT) != 0)
            [pCmd->mtlRenderEncoder setVertexBuffer:argumentBuffer->mtlBuffer offset:argumentBuffer->mPositionInHeap atIndex:descInfo->mDesc.reg];
        if ((descInfo->mDesc.used_stages & SHADER_STAGE_FRAG) != 0)
            [pCmd->mtlRenderEncoder setFragmentBuffer:argumentBuffer->mtlBuffer offset:argumentBuffer->mPositionInHeap atIndex:descInfo->mDesc.reg];
        if ((descInfo->mDesc.used_stages & SHADER_STAGE_COMP) != 0)
            [pCmd->mtlComputeEncoder setBuffer:argumentBuffer->mtlBuffer offset:argumentBuffer->mPositionInHeap atIndex:descInfo->mDesc.reg];
    }
    
    void util_end_current_encoders(Cmd* pCmd){
        if (pCmd->mtlRenderEncoder!=nil)
        {
            [pCmd->mtlRenderEncoder endEncoding];
            pCmd->mtlRenderEncoder = nil;
        }
        if (pCmd->mtlComputeEncoder!=nil)
        {
            [pCmd->mtlComputeEncoder endEncoding];
            pCmd->mtlComputeEncoder = nil;
        }
        if (pCmd->mtlBlitEncoder!=nil)
        {
            [pCmd->mtlBlitEncoder endEncoding];
            pCmd->mtlBlitEncoder = nil;
        }
    }
    
    bool util_sync_encoders(Cmd* pCmd, const CmdPoolType& newEncoderType){
        if (newEncoderType != CMD_POOL_DIRECT && pCmd->mtlRenderEncoder!=nil)
        {
            [pCmd->mtlRenderEncoder updateFence:pCmd->mtlEncoderFence afterStages:MTLRenderStageFragment];
            return true;
        }
        if (newEncoderType != CMD_POOL_COMPUTE && pCmd->mtlComputeEncoder!=nil)
        {
            [pCmd->mtlComputeEncoder updateFence:pCmd->mtlEncoderFence];
            return true;
        }
        if (newEncoderType != CMD_POOL_COPY && pCmd->mtlBlitEncoder!=nil)
        {
            [pCmd->mtlBlitEncoder updateFence:pCmd->mtlEncoderFence];
            return true;
        }
        return false;
    }
    
    void add_texture(Renderer* pRenderer, const TextureDesc* pDesc, Texture** ppTexture, const bool isRT){
        Texture* pTexture = (Texture*)conf_calloc(1, sizeof(*pTexture));
        ASSERT(pTexture);
        pTexture->pRenderer = pRenderer;
        pTexture->mDesc = *pDesc;
        pTexture->pCpuMappedAddress = NULL;
        pTexture->mTextureId = (++gTextureIds << 8U) + util_pthread_to_uint64(Thread::GetCurrentThreadID());
        pTexture->mtlPixelFormat = util_to_mtl_pixel_format(pTexture->mDesc.mFormat, pTexture->mDesc.mSrgb);
        pTexture->mIsCompressed = util_is_mtl_compressed_pixel_format(pTexture->mtlPixelFormat);
        pTexture->mTextureSize = Image::GetMipMappedSize(pTexture->mDesc.mWidth, pTexture->mDesc.mHeight, 1, 0, pTexture->mDesc.mMipLevels, pTexture->mDesc.mFormat);
        if (pTexture->mDesc.mHostVisible) {
            internal_log(LOG_TYPE_WARN, "Host visible textures are not supported, memory of resulting texture will not be mapped for CPU visibility", "addTexture");
        }
        
        // If we've passed a native handle, it means the texture is already on device memory, and we just need to assign it.
        if (pDesc->pNativeHandle)
        {
            pTexture->mOwnsImage = false;
            pTexture->mtlTexture = (id<MTLTexture>)CFBridgingRelease(pDesc->pNativeHandle);
        }
        // Otherwise, we need to create a new texture.
        else
        {
            pTexture->mOwnsImage = true;
            
            // Create a MTLTextureDescriptor that matches our requirements.
            MTLTextureDescriptor* textureDesc = [[MTLTextureDescriptor alloc] init];
            switch (pTexture->mDesc.mType) {
                case TEXTURE_TYPE_1D:
                    if(pTexture->mDesc.mArraySize == 1) textureDesc.textureType = MTLTextureType1D;
                    else textureDesc.textureType = MTLTextureType1DArray;
                    break;
                case TEXTURE_TYPE_2D:
                    if(pTexture->mDesc.mArraySize > 1) textureDesc.textureType = MTLTextureType2DArray;
                    else if(pTexture->mDesc.mSampleCount > 1) textureDesc.textureType = MTLTextureType2DMultisample;
                    else textureDesc.textureType = MTLTextureType2D;
                    break;
                case TEXTURE_TYPE_3D:
                    textureDesc.textureType = MTLTextureType3D;
                    break;
                case TEXTURE_TYPE_CUBE:
                    if(pTexture->mDesc.mArraySize == 1) textureDesc.textureType = MTLTextureTypeCube;
                    else textureDesc.textureType = MTLTextureTypeCubeArray;
                    break;
            }
            textureDesc.pixelFormat = pTexture->mtlPixelFormat;
            textureDesc.width = pTexture->mDesc.mWidth;
            if(pTexture->mDesc.mType > TEXTURE_TYPE_1D) textureDesc.height = pTexture->mDesc.mHeight;
            if(pTexture->mDesc.mType == TEXTURE_TYPE_3D) textureDesc.depth = pTexture->mDesc.mDepth;
            textureDesc.mipmapLevelCount = pTexture->mDesc.mMipLevels;
            textureDesc.sampleCount = pTexture->mDesc.mSampleCount;
            textureDesc.arrayLength = pTexture->mDesc.mArraySize;
            textureDesc.storageMode = MTLStorageModePrivate;
            textureDesc.cpuCacheMode = MTLCPUCacheModeDefaultCache;
            
            bool isDepthBuffer = util_is_mtl_depth_pixel_format(pTexture->mtlPixelFormat);
            bool isMultiSampled = pTexture->mDesc.mSampleCount > 1;
            if (isDepthBuffer || isMultiSampled) textureDesc.resourceOptions = MTLResourceStorageModePrivate;
            
            if (isRT || isDepthBuffer) textureDesc.usage |= MTLTextureUsageRenderTarget;
            if ((pTexture->mDesc.mUsage & TEXTURE_USAGE_UNORDERED_ACCESS) != 0) textureDesc.usage |= MTLTextureUsageShaderWrite;
            
            // Allocate the texture's memory.
            AllocatorMemoryRequirements mem_reqs = { 0 };
            mem_reqs.usage = (ResourceMemoryUsage)RESOURCE_MEMORY_USAGE_GPU_ONLY;
            if (pDesc->mFlags & TEXTURE_CREATION_FLAG_OWN_MEMORY_BIT)
                mem_reqs.flags |= RESOURCE_MEMORY_REQUIREMENT_OWN_MEMORY_BIT;
            if (pDesc->mFlags & TEXTURE_CREATION_FLAG_EXPORT_BIT)
                mem_reqs.flags |= RESOURCE_MEMORY_REQUIREMENT_SHARED_BIT;
            if (pDesc->mFlags & TEXTURE_CREATION_FLAG_EXPORT_ADAPTER_BIT)
                mem_reqs.flags |= RESOURCE_MEMORY_REQUIREMENT_SHARED_ADAPTER_BIT;
            
            TextureCreateInfo alloc_info = {textureDesc, isRT || isDepthBuffer, isMultiSampled};
            bool allocSuccess = createTexture(pRenderer->pResourceAllocator, &alloc_info, &mem_reqs, pTexture);
            ASSERT(allocSuccess);
        }
        
        *ppTexture = pTexture;
    }
    
    // -------------------------------------------------------------------------------------------------
    // Indirect draw functions
    // -------------------------------------------------------------------------------------------------
    void addIndirectCommandSignature(Renderer* pRenderer, const CommandSignatureDesc* pDesc, CommandSignature** ppCommandSignature)
    {
        assert(pRenderer!=nil);
        assert(pDesc!=nil);
        
        CommandSignature* pCommandSignature = (CommandSignature*)conf_calloc(1,sizeof(CommandSignature));
        
        for (uint32_t i=0; i< pDesc->mIndirectArgCount; i++)
        {
            const IndirectArgumentDescriptor* argDesc = pDesc->pArgDescs + i;
            if (argDesc->mType != INDIRECT_DRAW && argDesc->mType != INDIRECT_DISPATCH && argDesc->mType != INDIRECT_DRAW_INDEX)
            {
                assert(!"Unsupported indirect argument type.");
                SAFE_FREE(pCommandSignature);
                return;
            }
            
            if (i==0)
            {
                pCommandSignature->mDrawType = argDesc->mType;
            }
            else if (pCommandSignature->mDrawType != argDesc->mType)
            {
                assert(!"All elements in the root signature must be of the same type.");
                SAFE_FREE(pCommandSignature);
                return;
            }
        }
        pCommandSignature->mIndirectArgDescCounts = pDesc->mIndirectArgCount;
        
        *ppCommandSignature = pCommandSignature;
    }
    
    void removeIndirectCommandSignature(Renderer* pRenderer, CommandSignature* pCommandSignature)
    {
        ASSERT(pCommandSignature);
        SAFE_FREE(pCommandSignature);
    }
    
    void cmdExecuteIndirect(Cmd* pCmd, CommandSignature* pCommandSignature, uint maxCommandCount, Buffer* pIndirectBuffer, uint64_t bufferOffset, Buffer* pCounterBuffer, uint64_t counterBufferOffset)
    {
        for (uint32_t i=0; i<maxCommandCount; i++)
        {
            if (pCommandSignature->mDrawType == INDIRECT_DRAW)
            {
                uint64_t indirectBufferOffset = bufferOffset + sizeof(IndirectDrawArguments)*i;
                
                [pCmd->mtlRenderEncoder drawPrimitives:pCmd->selectedPrimitiveType
                                        indirectBuffer:pIndirectBuffer->mtlBuffer
                                  indirectBufferOffset:indirectBufferOffset];
            }
            else if (pCommandSignature->mDrawType == INDIRECT_DRAW_INDEX)
            {
                Buffer* indexBuffer = pCmd->selectedIndexBuffer;
                MTLIndexType indexType = (indexBuffer->mDesc.mIndexType == INDEX_TYPE_UINT16 ? MTLIndexTypeUInt16 : MTLIndexTypeUInt32);
                uint64_t indirectBufferOffset = bufferOffset + sizeof(IndirectDrawIndexArguments)*i;
                
                [pCmd->mtlRenderEncoder drawIndexedPrimitives:pCmd->selectedPrimitiveType
                                                    indexType:indexType
                                                  indexBuffer:indexBuffer->mtlBuffer
                                            indexBufferOffset:0
                                               indirectBuffer:pIndirectBuffer->mtlBuffer
                                         indirectBufferOffset:indirectBufferOffset];
            }
            else if (pCommandSignature->mDrawType == INDIRECT_DISPATCH)
            {
                //TODO: Implement.
                ASSERT(0);
            }
        }
    }
    
    /************************************************************************/
    // Debug Marker Implementation
    /************************************************************************/
    
    void cmdBeginDebugMarker(Cmd* pCmd, float r, float g, float b, const char* pName)
    {
        // TODO: Implement.
    }
    void cmdBeginDebugMarkerf(Cmd* pCmd, float r, float g, float b, const char* pFormat, ...)
    {
        // TODO: Implement.
    }
    
    void cmdEndDebugMarker(Cmd* pCmd)
    {
        // TODO: Implement.
    }
    
    void cmdAddDebugMarker(Cmd* pCmd, const char* pName, float r, float g, float b, float a)
    {
        // TODO: Implement.
    }
    
    /************************************************************************/
    /************************************************************************/
#endif // RENDERER_IMPLEMENTATION
    
#if defined(__cplusplus) && defined(RENDERER_CPP_NAMESPACE)
} // namespace RENDERER_CPP_NAMESPACE
#endif
#endif

