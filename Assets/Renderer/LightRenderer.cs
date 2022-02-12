using UnityEngine;
using UnityEngine.Rendering;
using Unity.Collections;

public class LightRenderer
{
    const string bufferName = "Lighting";
    CommandBuffer buffer = new CommandBuffer { name = bufferName };

    //灯光限制数量
    const int maxDirLightCount = 4;

    //数据ID
    static int
        dirLightCountId = Shader.PropertyToID("_DirectionalLightCount"),
        dirLightColorsId = Shader.PropertyToID("_DirectionalLightColors"),
        dirLightDirectionsId = Shader.PropertyToID("_DirectionalLightDirections");

    //绑定数据
    static Vector4[]
        dirLightColors = new Vector4[maxDirLightCount],
        dirLightDirections = new Vector4[maxDirLightCount];


    CullingResults cullingResults;

    public void Setup(ScriptableRenderContext context, CullingResults cullingResults)
    {
        this.cullingResults = cullingResults;

        buffer.BeginSample(bufferName);
        SetupLights();
        buffer.EndSample(bufferName);
        context.ExecuteCommandBuffer(buffer);
        buffer.Clear();
    }

    void SetupLights()
    {
        NativeArray<VisibleLight> visibleLights = cullingResults.visibleLights;
        int dirLightCount = 0;
        for (int i = 0; i < visibleLights.Length; ++i)
        {
            VisibleLight visibleLight = visibleLights[i];
            switch (visibleLight.lightType)
            {
                case LightType.Directional:
                    {
                        if (dirLightCount < maxDirLightCount)
                        {
                            SetupDirectionalLight(dirLightCount++, ref visibleLight);
                        }
                    }
                    break;
            }
        }

        //绑定数据
        buffer.SetGlobalInt(dirLightCountId, dirLightCount);
        if (dirLightCount > 0)
        {
            buffer.SetGlobalVectorArray(dirLightColorsId, dirLightColors);
            buffer.SetGlobalVectorArray(dirLightDirectionsId, dirLightDirections);
        }
    }

    void SetupDirectionalLight(int index, ref VisibleLight visibleLight)
    {
        dirLightColors[index] = visibleLight.finalColor;
        dirLightDirections[index] = Vector4.Normalize(-visibleLight.localToWorldMatrix.GetColumn(2));
    }

    public void Cleanup()
    {

    }
}
