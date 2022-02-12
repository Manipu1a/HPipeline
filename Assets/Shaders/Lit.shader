Shader"HPipeline/Lit"
{
    Properties
    {
        _BaseColor ("BaseColor", Color) = (1,1,1,1)
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
        _Metallic ("Metallic", Range(0,1)) = 0.0
        _Smoothness("Smoothness", Range(0,1)) = 0.5
        _Emissive("Emissive", Color) = (1,1,1,1)
        _Reflectance("Reflectance", Range(0, 1)) = 0.0
        _AmbientOcclusion("AmbientOcclusion", Range(0,1)) = 0.0
    }
    SubShader
    {
        HLSLINCLUDE
            #include "../ShaderLibrary/Common.hlsl"
            #include "LitInput.hlsl"
        ENDHLSL

        Pass
        {
            Tags
            {
                "LightMode" = "CustomLit"
            }

            Cull Back
            HLSLPROGRAM
            #pragma vertex LitVertex
            #pragma fragment LitFragment
            
            #include "../ShaderLibrary/BRDF.hlsl"

            struct Attributes
            {
                float3 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 baseUV : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : VAR_POSITION;
                float3 normalWS : VAR_NORMAL;
                float2 baseUV : VAR_BASE_UV;
            };

            Varyings LitVertex(Attributes input)
            {
                Varyings output;
                output.positionWS = TransformObjectToWorld(input.positionOS);
                output.positionCS = TransformWorldToHClip(output.positionWS);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.baseUV = TransformBaseUV(input.baseUV);
                return output;
            }

            float4 LitFragment(Varyings input) : SV_TARGET
            {
                Surface surface;
                surface.position = input.positionWS;
                surface.normal = normalize(input.normalWS);
                surface.viewDirection = normalize(_WorldSpaceCameraPos.xyz - input.positionWS);
                surface.color = _BaseColor.rgb;
                surface.alpha = _BaseColor.a;
                surface.metallic = _Metallic;
                surface.smoothness = _Smoothness;
                surface.reflectance = _Reflectance;
                surface.occlusion = _AmbientOcclusion;
                
                BRDF brdf = GetBRDF(surface);
                /*float3 uvw = reflect(-surface.viewDirection, surface.normal);
                float3 specular = SampleIrradiance(surface.normal);*/
                
                float3 color = IndirectBRDF(surface, brdf);
               // float3 color = float3(0.0,0.0,0.0);
                for (int i = 0; i < GetDirectionalLightCount(); ++i)
                {
                    Light light = GetDirectionalLight(i, surface);
                    color += DirectBrdf(surface, brdf, light);
                }

                color = color / (color + float3(1.0, 1.0, 1.0));
                color = pow(color, float3(1.0 / 2.2, 1.0 / 2.2,1.0 / 2.2));
                
                return float4(color, 1.0);
            }

            ENDHLSL
        }
    }
}
