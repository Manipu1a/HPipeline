#ifndef CUSTOM_BRDF_INCLUDED
#define CUSTOM_BRDF_INCLUDED

#include "../ShaderLibrary/Light.hlsl"

struct BRDF
{
    float3 diffuse;
    float3 specular;
    float roughness;
    float perceptualRoughness;
    float3 reflectance;
};

#define MIN_REFLECTIVITY 0.04

float OneMinusReflectivity(float metallic)
{
    float range = 1.0 - MIN_REFLECTIVITY;
    return range - metallic * range;
}

float3 GetF0(float3 albedo, float metallic, float reflectance)
{
    float3 f0 = 0.16f * reflectance * reflectance * (1.0 - metallic) + albedo * metallic;
    return f0;
}

BRDF GetBRDF(Surface surface)
{
    BRDF brdf;
    
    float oneMinusReflectivity = OneMinusReflectivity(surface.metallic);
    brdf.diffuse = surface.color * oneMinusReflectivity;
    brdf.specular = lerp(MIN_REFLECTIVITY, surface.color, surface.metallic);
    brdf.perceptualRoughness = clamp(PerceptualSmoothnessToPerceptualRoughness(surface.smoothness), 0.045f, 1);
    
    //因为在lut读取roughness=1f时有问题 所以clamp最大值
    brdf.roughness = clamp(PerceptualRoughnessToRoughness(brdf.perceptualRoughness), 0.045f, 0.999f);
    //brdf.roughness = PerceptualRoughnessToRoughness(brdf.perceptualRoughness);
    
    brdf.reflectance = GetF0(surface.color, surface.metallic, surface.reflectance);
    
    return brdf;
}
//D项
//GGX
float D_GGX(float NoH, float roughness)
{
    float a2 = roughness * roughness;
    float f = (NoH * a2 - NoH) * NoH + 1.0;
    return a2 / (f * f);
}

//优化版GGX
#define MEDIUMP_FLT_MAX    65504.0
#define satureMediump(x)   min(x, MEDIUMP_FLT_MAX)
float D_GGX(float roughness, float NoH, const float3 n, const float3 h)
{
    float3 NxH = cross(n, h);
    float a = NoH * roughness;
    float k = roughness / (dot(NxH, NxH) + a * a);
    float d = k * k * (1.0 / PI);
    return satureMediump(d);
}
//G项- GGX+Schlick-Beckmann
float GeometrySchlickGGX(float NdotV, float roughness)
{
    float a = roughness; //?
    float k = (a * a) / 2.0;
    
    float nom = NdotV;
    float denom = max(NdotV * (1.0 - k) + k, 0.001f);

    return nom / denom;
}
float GeometrySmith(float3 N, float3 V,float3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.001f);
    float NdotL = max(dot(N, L), 0.001f);
    float ggx1 = GeometrySchlickGGX(NdotV, roughness);
    float ggx2 = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

//V项标准版
float V_SmithGGXCorrelated(float NoV, float NoL, float roughness)
{
    float a2 = roughness * roughness;
    float GGXV = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
    float GGXL = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
    return 0.5f / (GGXV + GGXL);
    //return GGXV + GGXL;
}

//优化版
float V_SmithGGXCoorelatedFast(float NoV, float NoL, float roughness)
{
    float a = roughness;
    float GGXV = NoL * (NoV * (1.0 - a) + a);
    float GGXL = NoV * (NoL * (1.0 - a) + a);
    return 0.5 / (GGXV + GGXL);
}

//F-Schlick
float3 F_Schlick(float u, float3 f0, float f90)
{
    return f0 + (f90 - f0) * pow(1.0 - u, 5.0);
}

//Schlick，默认90度时反射率是1
float3 F_Schlick(float u, float3 f0)
{
    float f = pow(1.0 - u, 5.0);
    return f0 + f * (1.0 - f0);
}

float3 F_SchlickRoughness(float cosTheta, float3 f0, float roughness)
{
    float3 f = 1.0 - roughness;
    return f0 + (max(f, f0) - f0) * pow(1.0 - cosTheta, 5.0);
}

//Lambert diffuse 最简化的公式
float Fd_Lambert()
{
    return 1.0 / PI;
}

//Diffuse Burley brdf 
float Fd_Burley(float NoV, float NoL, float LoH, float roughness)
{
    float f90 = 0.5 + 2.0 * roughness * LoH * LoH;
    float3 f0 = float3(1.0f, 1.0f, 1.0f);
    float lightScatter = F_Schlick(NoL, f0, f90).r;
    float viewScatter = F_Schlick(NoV, f0, f90).r;
    return lightScatter * viewScatter * (1.0 / PI);
}

//Renormalized diffuse
float Fd_DisneyRenormalized(float NoV, float NoL, float LoH, float linearRoughness)
{
    float energyBias = lerp(0.0f, 0.5f, linearRoughness);
    
    float energyFactor = lerp(1.0f, 1.0f / 1.51f, linearRoughness);
    
    float f90 = energyBias + 2.0f * LoH * LoH * linearRoughness;
    
    float3 f0 = float3(1.0f, 1.0f, 1.0f);
    
    float lightScatter = F_Schlick(NoL, f0, f90).r;
    float ViewScatter = F_Schlick(NoV, f0, f90).r;

    return lightScatter * ViewScatter * energyFactor;
}

//预计算环境贴图-间接高光实时计算使用
float3 PreFilterEnvMap(TextureCube envMap, sampler samplerEnv, float LinearRoughness, float3 R)
{
    float3 prefilteredColor = (float3)0.0f;

    //假设N V R都是一个方向
    float3 N = R;
    float3 V = R;
    
    const uint SAMPLE_COUNT = 1024u;
    const float SPEC_TEX_WIDTH = 512;
                
    float totalWeight = 0.0;
    
    for(uint i = 0u; i < SAMPLE_COUNT; ++i)
    {
        float2 xi = Hammersley(i, SAMPLE_COUNT);
        float3 halfway = ImportanceSampleGGX(xi, N, LinearRoughness);
        //反向推导光线方向
        float3 lightVec = normalize(2.0 * dot(V, halfway) * halfway - V);
                    
        float NdotL = max(dot(N , lightVec), 0.0);
        float NdotH = saturate(dot(N, halfway));
        float HdotV = saturate(dot(halfway, V));
                    
        if(NdotL > 0.0)
        {
            //根据pdf来计算mipmap等级
            /*float D = D_GGX(NdotH, LinearRoughness);
            float pdf = (D * NdotH / (4 * HdotV) + 0.0001f);

            float saTexel = 4.0f * PI / (6.0f * SPEC_TEX_WIDTH * SPEC_TEX_WIDTH);
            float saSample = 1.0f / (SAMPLE_COUNT * pdf + 0.00001f);

            float mipLevel = LinearRoughness == 0.0f ? 0.0f : 0.5f * log2(saSample / saTexel);*/
            
            //prefilteredColor += envMap.SampleLevel(samplerEnv, lightVec, mipLevel).rgb * NdotL;
            prefilteredColor += SAMPLE_TEXTURECUBE(envMap, samplerEnv, lightVec) * NdotL;
            totalWeight += NdotL;
        }
    }
    //dw
    prefilteredColor = prefilteredColor / totalWeight;
    
    return prefilteredColor;
}

//预计算brdf项-间接高光实时计算使用
float2 IntegrateBRDF(float NdotV, float LinearRoughness)
{
    // Derive tangent-space viewing vector from angle to normal (pointing towards +Z in this reference frame).
    float3 V;
    V.x = max(sqrt(1.0 - NdotV * NdotV),0.001f);
    V.y = 0.0;
    V.z = NdotV;

    float A = 0.0;
    float B = 0.0;
    
    //这项计算是view independ的 所以固定N
    float3 N = float3(0.0,0.0,1.0);

    const uint SAMPLE_COUNT = 2048u;
    for(uint i = 0u;i < SAMPLE_COUNT;++i)
    {
        float2 xi = Hammersley(i, SAMPLE_COUNT);
        float3 halfway = ImportanceSampleGGX(xi, N, LinearRoughness);
        // halfway = SampleGGX(xi.x, xi.y, LinearRoughness);
        float3 lightVec = normalize(2.0 * dot(V, halfway) * halfway - V);
        
        float NdotL = saturate(lightVec.z);
        float NdotH = saturate(halfway.z);
        float VdotH = max(dot(V, halfway), 0.001f);
 
        if(NdotL > 0.0)
        {
            float G = GeometrySmith(N, V, lightVec, LinearRoughness);
            float G_Vis = (G * VdotH) / max((NdotH * NdotV), 0.001f);
            //float G_Vis = (G * VdotH) / NdotH;
            float Fc = pow(1.0 - VdotH, 5.0);
            A += G_Vis;
            B += Fc * G_Vis;
        }
    }
    A /= float(SAMPLE_COUNT);
    B /= float(SAMPLE_COUNT);
    
    return float2(A, B);
}

//直接光 brdf计算
float3 DirectBrdf(Surface surface, BRDF brdf, Light light)
{
    float3 L = light.direction.xyz;
    //
    float3 H = SafeNormalize(surface.viewDirection + L);
    float3 N = surface.normal;
    float3 V = surface.viewDirection;
    
    float NoV = (abs(dot(N, V)) + 1e-5);
    float NoL = saturate(dot(N, L));
    float NoH = saturate(dot(N, H));
    float LoH = saturate(dot(L, H));
    float VoH = saturate(dot(V, H));
    float G = GeometrySmith(N, V, L, brdf.perceptualRoughness);
    float G_Vis = (G * VoH) / (NoH * NoV);
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.001;

    
    //感知线性粗糙度到粗糙度
    //float roughness = brdf.perceptualRoughness * brdf.perceptualRoughness;
    //Direct BRDF
    float D = D_GGX(NoH, brdf.roughness);
    
    float3 f0 = brdf.reflectance;
    float3 F = F_Schlick(VoH, f0);
    float Vis = V_SmithGGXCorrelated(NoV, NoL, brdf.roughness);
    
    float3 nominator    = D * G * F;
    float3 specular     = nominator / denominator;
    
    //specular BRDF
    float3 Fr = D * F * Vis;
    //diffuse BRDF
    float3 Fd = brdf.diffuse * Fd_DisneyRenormalized(NoV, NoL, LoH, brdf.perceptualRoughness) / PI;

    float3 kS = F;
    float3 kD = 1.0 - kS;
    kD *= 1.0 - surface.metallic;
    
    return (kD * Fd + Fr) * light.color * NoL;
}

 //Indirect BRDF
float3 IndirectBRDF(Surface surface, BRDF brdf)
{
    float3 N = surface.normal;
    float3 V = surface.viewDirection;
    float3 R = reflect(-V, N);
    const float MAX_REFLECTION_LOD = 4.0;
    float NoV = clamp((abs(dot(N, V)) + 1e-5),0.001f, 1.0f);
    
    float3 f0 = brdf.reflectance;
    float3 kS = F_SchlickRoughness(NoV, f0, brdf.roughness);
    float3 kD = 1.0 - kS;
    kD *= 1.0 - surface.metallic;
    
    float3 irradiance = SampleIrradiance(N);
    float3 indirectDiffuse = irradiance * brdf.diffuse;
    
    //IBL-1
    float3 prefilteredColor = _PrefilterCubeMap.SampleLevel(sampler_PrefilterCubeMap, R, brdf.roughness * MAX_REFLECTION_LOD).rgb;
    //IBL-2
    float3 F = kS;
    float2 envBRDF = SAMPLE_TEXTURE2D(_BrdfLUT, sampler_BrdfLUT, float2(clamp(NoV, 0.001f,0.999f), 0.9f)).rg;
    
    float3 indirectSpecular = prefilteredColor * (F * envBRDF.x + envBRDF.y);
    
    float3 ambient = (kD * indirectDiffuse + indirectSpecular) * surface.occlusion;
    
    return float4(ambient,1.0) ;
    
}
#endif