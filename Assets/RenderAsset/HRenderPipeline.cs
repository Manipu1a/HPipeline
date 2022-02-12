using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

public class HRenderPipeline : RenderPipeline
{
    //CameraRenderer renderer = new CameraRenderer();

    public static HRenderPipelineSettings settings;

    private static readonly Dictionary<Camera, CameraRenderer> cameraRenderers = new Dictionary<Camera, CameraRenderer>(2);
    private static readonly List<KeyValuePair<Camera, CameraRenderer>> tempCameras = new List<KeyValuePair<Camera, CameraRenderer>>(10);

    public static Matrix4x4[] captureViews = 
    {
        Tools.LookAt(Vector3.zero, new Vector3(1.0f, 0.0f,0.0f), new Vector3(0.0f, -1.0f, 0.0f)),
        Tools.LookAt(Vector3.zero, new Vector3(-1.0f, 0.0f,0.0f), new Vector3(0.0f, -1.0f, 0.0f)),
        Tools.LookAt(Vector3.zero, new Vector3(0.0f, -1.0f,0.0f), new Vector3(0.0f, 0.0f, -1.0f)),
        Tools.LookAt(Vector3.zero, new Vector3(0.0f, 1.0f,0.0f), new Vector3(0.0f, 0.0f, 1.0f)),
        Tools.LookAt(Vector3.zero, new Vector3(0.0f, 0.0f,1.0f), new Vector3(0.0f, -1.0f, 0.0f)),
        Tools.LookAt(Vector3.zero, new Vector3(0.0f, 0.0f,-1.0f), new Vector3(0.0f, -1.0f, 0.0f)),
    };
    
    public HRenderPipeline(HRenderPipelineSettings settings)
    {
        HRenderPipeline.settings = settings;
    }

    public static void RequestCameraCheck()
    {
        foreach (var pair in cameraRenderers)
        {
            if (!pair.Key || pair.Value == null) tempCameras.Add(pair);
        }

        foreach (var pair in tempCameras)
        {
            cameraRenderers.Remove(pair.Key);
            pair.Value.Dispose();
        }

        tempCameras.Clear();
    }

    
    protected override void Render(ScriptableRenderContext context, Camera[] cameras)
    {
        RequestCameraCheck();
        var screenWidth = Screen.width;
        var screenHeight = Screen.height;
        
        BeginFrameRendering(context, cameras);

        foreach (Camera camera in cameras)
        {
            //var crect = camera.rect;
            var cameraRenderer = GetCameraRenderer(context, camera);
            
            //cameraRenderer.SetResolutionAndRation(screenWidth, screenHeight, 1.0f, 1.0f);
            BeginCameraRendering(context, camera);
            cameraRenderer.Render(context);
            
            EndCameraRendering(context, camera);
        }

        EndFrameRendering(context, cameras);
    }

    internal CameraRenderer GetCameraRenderer(ScriptableRenderContext context, Camera camera)
    {
        if(!cameraRenderers.TryGetValue(camera, out var renderer))
        {
            renderer = CameraRenderer.CreateCameraRenderer(context, camera);
            //将初始化Buffer移动至创建时 
            //renderer.SetUp();
            //renderer.PreCalculatePass();
            
            cameraRenderers.Add(camera, renderer);
        }

        return renderer;
    }

    protected override void Dispose(bool disposing)
    {
        foreach (var renderer in cameraRenderers.Values) renderer.Dispose();
        cameraRenderers.Clear();
        base.Dispose(disposing);
    }
}

public static class ShaderIDManager
                                             {
    public static readonly int globalEnvCubeMap = Shader.PropertyToID("_GlobalEnvCubeMap");

    public static readonly int irradianceCubeMap = Shader.PropertyToID("_IrradianceCubeMap");

    public static readonly int prefilterCubeMap = Shader.PropertyToID("_PrefilterCubeMap");

    public static readonly int prefilterBrdfLut = Shader.PropertyToID("_BrdfLUT");
    
    public static readonly int roughness = Shader.PropertyToID("_PrefilterRoughness");
    
    public static readonly int CubeMapTest = Shader.PropertyToID("_CubeMapTest");

    public static readonly int lut = Shader.PropertyToID("_LUT");

    public static readonly int lutStep = Shader.PropertyToID("_Step");
                                             }
