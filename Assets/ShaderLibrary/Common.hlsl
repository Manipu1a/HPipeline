#ifndef CUSTOM_UNLIT_COMMON_INCLUDED
#define CUSTOM_UNLIT_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Sampling/Hammersley.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Sampling/Sampling.hlsl"

#define UNITY_MATRIX_M unity_ObjectToWorld
#define UNITY_MATRIX_I_M unity_WorldToObject
#define UNITY_MATRIX_V unity_MatrixV
#define UNITY_MATRIX_VP unity_MatrixVP
#define UNITY_MATRIX_P glstate_matrix_projection
#define UNITY_PREV_MATRIX_M unity_PrevObjectToWorld
#define UNITY_PREV_MATRIX_I_M unity_PrevWorldToObjectMatrix
#define UNITY_MATRIX_I_V unity_ViewToWorldMatrix

CBUFFER_START(UnityPerDraw)
float4x4 unity_ObjectToWorld;
float4x4 unity_WorldToObject;
float4 unity_LODFade;
float4 unity_WorldTransformParams;
CBUFFER_END

float4x4 unity_MatrixVP; //ViewProjection Matrix
float4x4 unity_MatrixV;
float4x4 glstate_matrix_projection;
float3 _WorldSpaceCameraPos;
float4x4 unity_PrevObjectToWorld;
float4x4 unity_PrevWorldToObjectMatrix;
float4x4 unity_ViewToWorldMatrix;

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"


//最多支持四盏平行光
#define MAX_DIRECTIONAL_LIGHT_COUNT 4
//Light数据缓冲区
CBUFFER_START(UnityLightBuffer)
int _DirectionalLightCount;
float4 _DirectionalLightColors[MAX_DIRECTIONAL_LIGHT_COUNT];
float4 _DirectionalLightDirections[MAX_DIRECTIONAL_LIGHT_COUNT];
CBUFFER_END

static const float TwoPI = 2 * PI;

//struct Light
//{
//    float3 color;
//    float3 direction;
//};

struct Surface
{
    float3 position;
    float3 normal;
    float3 interpolatedNormal;
    float3 viewDirection;
    float depth;
    float3 color;
    float alpha;
    float metallic;
    float occlusion;
    float smoothness;
    float reflectance;
    float fresnelStrength;
    float dither;
};

CBUFFER_START(UnityPerMaterial)
float4 _MainTex_ST;
float4 _BaseColor;
float _Smoothness;
float _Metallic;
float4 _EmissiveColor;
float _Reflectance;
float _AmbientOcclusion;
CBUFFER_END

//TEXTURE2D(_MainTex);
//SAMPLER(sampler_BaseMap);
//环境立方体贴图
TEXTURECUBE(_GlobalEnvCubeMap);
SAMPLER(sampler_GlobalEnvCubeMap);
//预处理立方体贴图
TEXTURECUBE(_IrradianceCubeMap);
SAMPLER(sampler_IrradianceCubeMap);
//预计算IBL
TEXTURECUBE(_PrefilterCubeMap);
SAMPLER(sampler_PrefilterCubeMap);
TEXTURE2D(_BrdfLUT);
SAMPLER(sampler_BrdfLUT);

float _PrefilterRoughness;

float2 TransformBaseUV(float2 baseUV)
{
    return baseUV * _MainTex_ST.xy + _MainTex_ST.zw;
}

//VertexID转换坐标 
float4 VertexIDToPosCS(uint vertexID)
{
    return float4(
        vertexID <= 1 ? -1.0f : 3.0f,
        vertexID == 1 ? 3.0f : -1.0f,
        .0f,
        1.0f);
}

float2 VertexIDToScreenUV(uint vertexID)
{
    return float2(
        vertexID <= 1 ? .0f : 2.0f,
        vertexID == 1 ? 2.0f : .0f);
}

float3 SampleEnvironment(float3 Dir, float mipmap = 0.0)
{
    float4 environment = _GlobalEnvCubeMap.SampleLevel(sampler_GlobalEnvCubeMap, Dir, mipmap);

    return environment.rgb;
}

float3 SampleIrradiance(float3 Dir)
{
    float4 environment = _IrradianceCubeMap.SampleLevel(sampler_IrradianceCubeMap, Dir, 0.0);

    return environment.rgb;
}

//低差异序列
float RadicalInverse_VdC(uint bits)
{
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10; // / 0x100000000
}
float2 Hammersley(uint i, uint N)
{
    return float2(float(i) / float(N), RadicalInverse_VdC(i));
}

//使用GGX NDF来构建重要性采样向量
float3 ImportanceSampleGGX(float2 Xi, float3 N, float LinearRoughness)
{
    float a = LinearRoughness * LinearRoughness;
    
    float phi = 2.0 * PI * Xi.x;
    float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a * a - 1.0) * Xi.y));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

    // from spherical coordinates to cartesian coordinates
    float3 H;
    H.x = cos(phi) * sinTheta;
    H.y = sin(phi) * sinTheta;
    H.z = cosTheta;

    // from tangent-space vector to world-space sample vector
    float3 up = abs(N.z) < 0.999 ? float3(0.0,0.0,1.0) : float3(1.0,0.0,0.0);
    float3 tangent = normalize(cross(up, N));
    float3 bitangent = cross(N, tangent);

    float3 sampleVec = tangent * H.x + bitangent * H.y + N * H.z;
    return normalize(sampleVec);
}

float3 SampleGGX(float u1,float u2, float roughness)
{
    float alpha = roughness * roughness;

    float cosTheta = sqrt((1.0 - u2) / (1.0 + (alpha*alpha - 1.0) * u2));
    float sinTheta = sqrt(1.0 - cosTheta*cosTheta); // Trig. identity
    float phi = TwoPI * u1;

    // Convert to Cartesian upon return.
    return float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
}

#endif