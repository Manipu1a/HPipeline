Shader"Hidden/HIrradiance"
{
    Properties
    {

    }
    SubShader
    {
        HLSLINCLUDE
            #include "../ShaderLibrary/Common.hlsl"
        ENDHLSL

        Pass
        {
            Name "IrradianceCubemap"
            
            Tags
            {
               "LightMode" = "IrradianceCubemap"
            }

            Cull Off
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Fragment

            struct VertexInput
            {
                float3 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 baseUV : TEXCOORD0;
                
            };

            struct VertexOutput
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : VAR_POSITION;
                float3 normalWS : VAR_NORMAL;
                float2 baseUV : VAR_BASE_UV;
                
                float3 ray : TEXCOORD0;
            };

            VertexOutput Vert(VertexInput input)
            {
                VertexOutput output;
                output.positionWS = TransformObjectToWorld(input.positionOS);
                output.positionCS = TransformWorldToHClip(output.positionWS);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.baseUV = TransformBaseUV(input.baseUV);
                output.ray =  normalize(input.positionOS);
                return output;
            }

            float4 Fragment(VertexOutput input) : SV_TARGET
            {
                Surface surface;
                surface.position = input.positionWS;
                surface.normal = normalize(input.normalWS);
                surface.viewDirection = normalize(_WorldSpaceCameraPos.xyz - input.positionWS);
                //float4 environment = _GlobalEnvCubeMap.SampleLevel(sampler_GlobalEnvCubeMap, input.ray, 0.0);
                //float3 specular = SampleEnvironment(surface);
                float3 irradiance = float3(0.0,0.0,0.0);
                float3 up = float3(0.0,1.0,0.0);
                float3 right = cross(up, input.ray);
                up = cross(input.ray, right);

                float sampleDelta = 0.025;
                float nrSamples = 0.0;
                for(float phi = 0.0;phi < 2.0 * PI; phi += sampleDelta)
                {
                    for(float theta = 0.0;theta < 0.5 * PI; theta += sampleDelta)
                    {
                        float3 tangentSample = float3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));

                        float3 sampleVec = tangentSample.x * right + tangentSample.y * up + tangentSample.z * input.ray;
                        
                        irradiance += SampleEnvironment(sampleVec) * cos(theta) * sin(theta);
                        nrSamples++;
                    }
                    
                }
                irradiance = PI * irradiance * (1.0 / (float)nrSamples);
                
                return float4(irradiance,1.0);
            }

            ENDHLSL
        }
    }
}
