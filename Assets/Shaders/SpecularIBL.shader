Shader"Hidden/HSpecularIBL"
{
    Properties
    {
        //_PrefilterRoughness("PrefilterRoughness", Range(0,1)) = 0.5
    }
    
    SubShader
    {
        HLSLINCLUDE
           #include "../ShaderLibrary/Common.hlsl"
        ENDHLSL
        
        Pass
        {
            Name "PrefilterCubeMap"
            
            Tags
            {
               "LightMode" = "PrefilterCubeMap"
            }

            Cull Off
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Fragment
            #include "../ShaderLibrary/BRDF.hlsl"
            //float _PrefilterRoughness;
            
            struct VertexInput
            {
                float3 positionOS : POSITION;
            };

            struct VertexOutput
            {
                float4 positionCS : SV_POSITION;
                
                float3 ray : TEXCOORD0;
            };
            
            VertexOutput Vert(VertexInput input)
            {
                VertexOutput output;
                float3 positionWS = TransformObjectToWorld(input.positionOS);
                output.positionCS = TransformWorldToHClip(positionWS);

                output.ray =  normalize(input.positionOS);
                
                return output;
            }

            float4 Fragment(VertexOutput input) : SV_TARGET
            {
                float3 prefilteredColor = PreFilterEnvMap(_GlobalEnvCubeMap, sampler_GlobalEnvCubeMap, _PrefilterRoughness,input.ray );
                
                return float4(prefilteredColor, 1.0);
            }

            ENDHLSL
        }
        
    }
}
