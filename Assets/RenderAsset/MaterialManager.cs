using UnityEngine;

public class MaterialManager
{

    public static Material IrradianceCubeMapMat
    {
        get
        {
            if (irradianceCubeMapMat == null)
            {
                if (!HRenderPipeline.settings.irradianceShader) HRenderPipeline.settings.irradianceShader = Shader.Find("Hidden/HIrradiance");
                irradianceCubeMapMat = new Material(HRenderPipeline.settings.irradianceShader)
                {
                    hideFlags = HideFlags.HideAndDontSave
                };
            }
            return irradianceCubeMapMat;
        }
    }
    private static Material irradianceCubeMapMat;

    public static Material SpecularIBlMat
    {
        get
        {
            if (specularIBLMat == null)
            {
                if (!HRenderPipeline.settings.specularIBLShader) HRenderPipeline.settings.specularIBLShader = Shader.Find("Hidden/HSpecularIBL");
                specularIBLMat = new Material(HRenderPipeline.settings.specularIBLShader)
                {
                    hideFlags = HideFlags.HideAndDontSave
                };
            }

            return specularIBLMat;
        }
        
    }

    private static Material specularIBLMat;
    
    
    public static readonly int IRRADIANCE_CUBEMAP_PASS = IrradianceCubeMapMat.FindPass("IrradianceCubemap");
    public static readonly int PREFILTER_CUBEMAP_PASS = SpecularIBlMat.FindPass("PrefilterCubeMap");

}
