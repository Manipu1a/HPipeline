using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Serialization;

[CreateAssetMenu(menuName = "Rendering/HPipeline")]
public class HPipelineAsset : RenderPipelineAsset
{
    public HRenderPipelineSettings settings;

    protected override RenderPipeline CreatePipeline()
    {
        return new HRenderPipeline(settings);
    }
}


[Serializable]
public class HRenderPipelineSettings
{
    [Header("Image Based Lighting")]
    public Texture globalEnvMapDiffuse;

    [SerializeField] 
    public Texture LutTex;
    public Shader irradianceShader;
    public Shader specularIBLShader;
    
    [SerializeField]
    public Mesh mesh = default;

    [SerializeField]
    public RenderTexture irradianceEnvCubeMap;
    [SerializeField]
    public RenderTexture preFilterCubeMap;
    [SerializeField] 
    public RenderTexture Lut;

    [SerializeField] 
    public ComputeShader CSIntegrateBRDF;
}