using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;
using UnityEditor;
//摄像机渲染
public class CameraRenderer
{
    //渲染上下文
    ScriptableRenderContext context;
    //当前渲染的摄像机
    public Camera camera;
    
    const string bufferName = "Render Camera";

    CommandBuffer buffer = new CommandBuffer { name = bufferName };
    public static HRenderPipelineSettings settings => HRenderPipeline.settings;

    //cull结果
    CullingResults cullingResults;

    static ShaderTagId litShaderTagId = new ShaderTagId("CustomLit");

    LightRenderer lighting = new LightRenderer();

    //采用交换链的RTSystem
    BufferedRTHandleSystem rtBufferHandleSystem = new BufferedRTHandleSystem();
    //RTHandleSystem rtSys = new RTHandleSystem();

    private bool bPreCalculate = false;

    private ComputeBuffer lutBuffer;
    
    public Vector2Int OutputRes
    {
        get => _outputRes;
        set
        {
            if (_outputRes == value) return;
            _outputRes = value;
            UpdateRenderScale();
        }
    }

    public Vector2Int InternalRes => _internalRes;

    public Vector2Int CubeMapRes
    {
        get
        {
            return new Vector2Int(512, 512);
        }
    }
    
    public Vector2Int TexRes
    {
        get
        {
            return new Vector2Int(512, 512);
        }
    }

    public Vector2 Ratio
    {
        get => _ratio;
        set
        {
            if (_ratio == value || value.x > 1 || value.y > 1) return;
            _ratio = value;
            UpdateRenderScale(false);
        }
    }

    protected Vector2Int _outputRes;
    protected Vector2Int _internalRes;
    protected Vector2 _ratio;

    //RT Handles
    private RTHandle rthIrradianceCubeMap;

    private RTHandle rthPreFilterCubeMap;

    private RTHandle rthPreFilterBrdfLut;
    
    //RTHandle rthCubeMap;
    public CameraRenderer(Camera camera,ScriptableRenderContext context)
    {
        this.camera = camera;
        this.context = context;   
        
        camera.forceIntoRenderTexture = true;

        SetResolutionAndRation(camera.pixelWidth, camera.pixelHeight, 1.0f, 1.0f);

        InitBuffers();

        bPreCalculate = true;
        
        
    }
    
    protected virtual void UpdateRenderScale(bool outputChanged = true)
    {
        _internalRes = Vector2Int.CeilToInt(OutputRes * Ratio);
        Debug.Log("OutputRes!" + OutputRes);
        Debug.Log("InternalRes!" + InternalRes);
    }

    public void SetResolutionAndRation(int w, int h, float x, float y)
    {
        _outputRes = new Vector2Int(w, h);
        _ratio = new Vector2(x, y);

        Debug.Log("Ratio!" + Ratio);
        
        UpdateRenderScale(true);
    }
    
    public void Render(ScriptableRenderContext context)
    {
        this.context = context;
        
#if UNITY_EDITOR
        if (camera.cameraType == CameraType.SceneView)
        {
            ScriptableRenderContext.EmitWorldGeometryForSceneView(camera);
        }
#endif
        
        SetUp();
        if (camera.TryGetCullingParameters(out ScriptableCullingParameters p))
        {
            cullingResults = context.Cull(ref p);
            lighting.Setup(context, cullingResults);
            
            if (bPreCalculate)
            {
                PreCalculatePass();
                DrawIndirectSpecularEnvMapPass();
            }
            
            camera.ResetProjectionMatrix();
            context.SetupCameraProperties(camera);
            
            buffer.SetGlobalTexture(ShaderIDManager.irradianceCubeMap, rthIrradianceCubeMap);
            buffer.SetGlobalTexture(ShaderIDManager.prefilterCubeMap, rthPreFilterCubeMap);
            //buffer.SetGlobalTexture(ShaderIDManager.prefilterBrdfLut, HRenderPipeline.settings.LutTex);
            buffer.SetGlobalTexture(ShaderIDManager.prefilterBrdfLut,rthPreFilterBrdfLut);
            DrawVisibleGeometry();
    
            lighting.Cleanup();
        }
        
        
        if (bPreCalculate)
        {
            Graphics.CopyTexture(rthIrradianceCubeMap,HRenderPipeline.settings.irradianceEnvCubeMap);
            Graphics.CopyTexture(rthPreFilterBrdfLut, HRenderPipeline.settings.Lut);
            /*for (int i = 0; i < 1; ++i)
            {
                for (int element = 0; element < 6; ++element)
                {
                    Graphics.CopyTexture(rthPreFilterCubeMap, element, srcMip: i, HRenderPipeline.settings.preFilterCubeMap,element, dstMip:i);
                }
            }*/
            
            if (lutBuffer != null && lutBuffer.IsValid())
            {
                
            }
            bPreCalculate = false;
        }
        bPreCalculate = false;
        ExecuteCommand();
        SubmitContext();
    }

    //初始化
    public void SetUp()
    {
        //context.SetupCameraProperties(camera);
        GetBuffers();
        
        CameraClearFlags clearFlags = camera.clearFlags;
        //清屏
        buffer.ClearRenderTarget(clearFlags == CameraClearFlags.Depth, 
            clearFlags == CameraClearFlags.Color, clearFlags == CameraClearFlags.Color ? camera.backgroundColor.linear : Color.clear);
        buffer.BeginSample(bufferName);

        //设置全局变量
        buffer.SetGlobalTexture(ShaderIDManager.globalEnvCubeMap, settings.globalEnvMapDiffuse);

        ExecuteCommand();
    }

    //初始化RT
    void InitBuffers()
    {
        rtBufferHandleSystem.ResetReferenceSize(OutputRes.x, OutputRes.y);
        var ratio = rtBufferHandleSystem.CalculateRatioAgainstMaxSize(OutputRes.x, OutputRes.y);
        //Debug.Log("Reset!" + ratio);

        //Debug.Log("InternalRes!!!" + _internalRes);
        //分配rt handle
        rtBufferHandleSystem.AllocBuffer(ShaderIDManager.irradianceCubeMap,
            (rtHandleSys, i) => rtHandleSys.Alloc(size => CubeMapRes, colorFormat: GraphicsFormat.R16G16B16A16_SFloat,
            filterMode: FilterMode.Trilinear,dimension: TextureDimension.Cube, name: "IrradianceCubeMap"), 1);

        rtBufferHandleSystem.AllocBuffer(ShaderIDManager.prefilterCubeMap,
            (rtHandlesSys, i) => rtHandlesSys.Alloc(size => CubeMapRes, colorFormat: GraphicsFormat.R16G16B16A16_SFloat,
                filterMode: FilterMode.Trilinear, dimension: TextureDimension.Cube, useMipMap: true,
                autoGenerateMips: false, name: "PreFilterCubeMap", enableRandomWrite: true), 1);
        
        rtBufferHandleSystem.AllocBuffer(ShaderIDManager.prefilterBrdfLut,
            (rtHandlesSys, i) => rtHandlesSys.Alloc( size => TexRes, colorFormat: GraphicsFormat.R16G16B16A16_SFloat,
                filterMode: FilterMode.Bilinear, dimension: TextureDimension.Tex2D,  name: "PreFilterCubeMap", enableRandomWrite: true), 1);
    }
    
    public void ResetBufferSize()
    {
        // Debug.Log("Reset!");
        // Debug.Log(Time.frameCount + ", " + _frameNum + " " + camera.name + " Reset to " + OutputRes);
        // _historyBuffers.SwapAndSetReferenceSize(OutputRes.x, OutputRes.y);
        rtBufferHandleSystem.ResetReferenceSize(OutputRes.x, OutputRes.y);
    }
    
    //从buffer中获取rt handle
    void GetBuffers()
    {
        //设置关联大小
        rtBufferHandleSystem.SwapAndSetReferenceSize(OutputRes.x , OutputRes.y);

        rthIrradianceCubeMap = rtBufferHandleSystem.GetFrameRT(ShaderIDManager.irradianceCubeMap, 0);
        rthPreFilterCubeMap = rtBufferHandleSystem.GetFrameRT(ShaderIDManager.prefilterCubeMap, 0);
        rthPreFilterBrdfLut = rtBufferHandleSystem.GetFrameRT(ShaderIDManager.prefilterBrdfLut, 0);
    }
    public void PreCalculatePass()
    {
        DrawIrradianceMapPass();
        DrawIndirectSpecularBRDFPass();
    }
    
    void DrawIrradianceMapPass()
    {
        if (!HRenderPipeline.settings.mesh || HRenderPipeline.captureViews.Length != 6)
            return;
        
        for (int i = 0;i < 6;++i)
        {
            buffer.SetProjectionMatrix(Matrix4x4.Perspective(90.0f, 1.0f, 0.1f, 10.0f));
            buffer.SetViewMatrix(HRenderPipeline.captureViews[i]);
            buffer.SetRenderTarget(rthIrradianceCubeMap, 0, CubemapFace.PositiveX + i , 0);
            buffer.DrawMesh(HRenderPipeline.settings.mesh, Matrix4x4.identity, MaterialManager.IrradianceCubeMapMat, 0, MaterialManager.IRRADIANCE_CUBEMAP_PASS, null);
        } 
        buffer.ClearRenderTarget(true, false, Color.clear);
        ExecuteCommand();
    }
     
    //间接高光环境光Light预计算
    void DrawIndirectSpecularEnvMapPass()
    {
        if (!HRenderPipeline.settings.mesh || HRenderPipeline.captureViews.Length != 6)
            return;
        int maxMipLevels = 5;

        for (int mip = 0; mip < maxMipLevels; ++mip)
        {
            float roughness = (float) mip / (float) (maxMipLevels - 1);
            //MaterialManager.SpecularIBlMat.SetFloat(ShaderIDManager.roughness, roughness);
            for (int i = 0; i < 6; ++i)
            {
                //MaterialManager.SpecularIBlMat.SetFloat(ShaderIDManager.roughness, roughness);
                buffer.SetGlobalFloat(ShaderIDManager.roughness, roughness);
                buffer.SetProjectionMatrix(Matrix4x4.Perspective(90.0f, 1.0f, 0.1f, 10.0f));
                buffer.SetViewMatrix(HRenderPipeline.captureViews[i]);
                buffer.SetRenderTarget(rthPreFilterCubeMap, mip, (CubemapFace) i);
                buffer.DrawMesh(HRenderPipeline.settings.mesh, Matrix4x4.identity, MaterialManager.SpecularIBlMat,
                    0, MaterialManager.PREFILTER_CUBEMAP_PASS);
            }
            // buffer.ClearRenderTarget(true, true, Color.clear);
            ExecuteCommand();
        }
    }
    
    void DrawIndirectSpecularBRDFPass()
    {
        if (HRenderPipeline.settings.CSIntegrateBRDF)
        {
            int bufferSize = TexRes.x;
            float step = 1.0f / TexRes.x;
            HRenderPipeline.settings.CSIntegrateBRDF.SetFloat(ShaderIDManager.lutStep, step);
            HRenderPipeline.settings.CSIntegrateBRDF.SetTexture(0, ShaderIDManager.lut,  rthPreFilterBrdfLut);
            int groups = Mathf.CeilToInt(bufferSize / 32f);
            HRenderPipeline.settings.CSIntegrateBRDF.Dispatch(0, groups,groups,1);
        }
        
        ExecuteCommand();
    }
    void DrawVisibleGeometry()
    {
        CameraClearFlags clearFlags = camera.clearFlags;
        buffer.ClearRenderTarget(clearFlags == CameraClearFlags.Depth, clearFlags == CameraClearFlags.Color, clearFlags == CameraClearFlags.Color ? camera.backgroundColor.linear : Color.clear);
        ExecuteCommand();

        buffer.SetRenderTarget(camera.targetTexture);
        ExecuteCommand();
        //CoreUtils.SetViewport(buffer, camera.targetTexture);
        //排序方法
        var sortingSettings = new SortingSettings(camera) { criteria = SortingCriteria.CommonOpaque };

        var drawingSettings = new DrawingSettings(litShaderTagId, sortingSettings);

        var filteringSettings = new FilteringSettings(RenderQueueRange.opaque);
        
        context.DrawRenderers(cullingResults, ref drawingSettings, ref filteringSettings);
        context.DrawSkybox(camera);
        ExecuteCommand();
    }
    //
    void SubmitContext()
    {
        buffer.EndSample(bufferName);
        //buffer.DrawProcedural

        ExecuteCommand();
        //提交到gpu
        context.Submit();
    }

    //
    void ExecuteCommand()
    {
        //记录buffer中的命令
        context.ExecuteCommandBuffer(buffer);
        buffer.Clear();
    }

    public void Dispose()
    {
        //lutBuffer.Release();
        rtBufferHandleSystem.ReleaseAll();
        rtBufferHandleSystem.Dispose();
    }
    public static CameraRenderer CreateCameraRenderer(ScriptableRenderContext context, Camera camera)
    {
        return new CameraRenderer(camera,context);
    }
}
