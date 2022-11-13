using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering.Universal;
public class RaytracingRenderPass : ScriptableRenderPass
{
    string profilerTag;

    RTHandle currentTarget;
    RenderTexture resultTexture;
    RayTracingShader rayTracingShader;
    Material blendMat;

    LayerMask updateLayers;

    public static RayTracingAccelerationStructure accelerationStructure;

    private CommandBuffer command;

    Shader globalParams;

    float _frameIndex;

    bool init = false;

    public RaytracingRenderPass(string profilerTag, RenderPassEvent renderPassEvent, RayTracingShader shader, Material blendMat, LayerMask mask)
    {
        this.profilerTag = profilerTag;
        updateLayers = mask;
        rayTracingShader = shader;
        this.renderPassEvent = renderPassEvent;
        this.blendMat = blendMat;

        var settings = new RayTracingAccelerationStructure.RASSettings();
        settings.layerMask = updateLayers;
        settings.managementMode = RayTracingAccelerationStructure.ManagementMode.Automatic;
        settings.rayTracingModeMask = RayTracingAccelerationStructure.RayTracingModeMask.Everything;

        accelerationStructure = new RayTracingAccelerationStructure(settings);
        var stack = VolumeManager.instance.stack;
        m_rayTracing = stack.GetComponent<Raytracing>();
        if (m_rayTracing == null) return;
        if (!m_rayTracing.IsActive()) return;
        m_rayTracing.RetrieveInstances(ref accelerationStructure);

        _frameIndex = 0;
        init = true;
    }

    public void Setup(in RTHandle currentTarget)
    {
        this.currentTarget = currentTarget;
    }

    Raytracing m_rayTracing;

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        if (!renderingData.cameraData.postProcessEnabled) return;
        var stack = VolumeManager.instance.stack;
        m_rayTracing = stack.GetComponent<Raytracing>();
        if (m_rayTracing == null) return;
        if (!m_rayTracing.IsActive()) return;

        if(accelerationStructure.GetInstanceCount() == 0) m_rayTracing.RetrieveInstances(ref accelerationStructure);
        accelerationStructure.Build();

        command = CommandBufferPool.Get(profilerTag);
        if(init)
            InitCommandBuffer();

        _frameIndex += Time.deltaTime*60f;

        if(m_rayTracing.UpdateParameters)
            UpdateCommandBuffer(ref renderingData);
        Render(ref renderingData);
        context.ExecuteCommandBuffer(command);
        CommandBufferPool.Release(command);
    }

    void InitResultTexture(int width, int height)
    {
        if (resultTexture == null || resultTexture.width != width || resultTexture.height != height)
        {
            if (resultTexture != null)
                resultTexture.Release();

            resultTexture = new RenderTexture(width, height, 0, RenderTextureFormat.DefaultHDR, RenderTextureReadWrite.Linear);
            resultTexture.enableRandomWrite = true;
            resultTexture.Create();     

            InitCommandBuffer();
        }
    }

    void InitCommandBuffer()
    {        
        command.SetRayTracingShaderPass(rayTracingShader, "MyRaytracingPass");
        command.SetRayTracingAccelerationStructure(rayTracingShader, "_RaytracingAccelerationStructure", accelerationStructure);
    }

    void UpdateCommandBuffer(ref RenderingData renderingData)
    {
        ref var cameraData = ref renderingData.cameraData;

        var _camera = cameraData.camera;
        
        command.SetRayTracingIntParam(rayTracingShader, "_cullBackfaces", m_rayTracing.CullBackfaces.GetValue<bool>() ? 1 : 0);
        
        command.SetRayTracingMatrixParam(rayTracingShader, "_CameraToWorld", _camera.cameraToWorldMatrix);
        command.SetRayTracingMatrixParam(rayTracingShader, "_CameraInverseProjection", _camera.projectionMatrix.inverse);

        command.SetRayTracingIntParam(rayTracingShader, "_FrameIndex", Mathf.FloorToInt(_frameIndex));
        command.SetRayTracingVectorParam(rayTracingShader, "bottomColor", m_rayTracing.floorColor.GetValue<Color>());
        command.SetRayTracingVectorParam(rayTracingShader, "skyColor", m_rayTracing.skyColor.GetValue<Color>());
        command.SetRayTracingFloatParam(rayTracingShader, "_IndirectSkyStrength", m_rayTracing.IndirectSkyStrength.GetValue<float>());

        if(RenderSettings.skybox != null && RenderSettings.skybox.HasTexture("_Tex") && m_rayTracing.UseSkybox.GetValue<bool>())
        {
            command.SetGlobalTexture("g_EnvTex", RenderSettings.skybox.GetTexture("_Tex"));
            command.SetRayTracingIntParam(rayTracingShader, "_useSkyBox", 1);
        }
        else
        {
            command.SetRayTracingIntParam(rayTracingShader, "_useSkyBox", 0);
        }
        

        Shader.SetGlobalInteger("_maxReflectDepth", m_rayTracing.MaxReflections.GetValue<int>());
        Shader.SetGlobalInteger("_maxIndirectDepth", m_rayTracing.MaxIndirect.GetValue<int>());
        Shader.SetGlobalInteger("_maxRefractionDepth", m_rayTracing.MaxRefractions.GetValue<int>());
        Shader.SetGlobalInteger("_renderShadows", m_rayTracing.RaytracedShadows.GetValue<int>());
        Shader.SetGlobalInteger("_useDropShadows", m_rayTracing.DropShadows.GetValue<bool>() ? 1 : 0);
        Shader.SetGlobalInteger("_halfTraceReflections", m_rayTracing.HalfTraceReflections.GetValue<bool>() ? 1 : 0);
        Shader.SetGlobalInteger("_cullShadowBackfaces", m_rayTracing.DoubleSidedShadows.GetValue<bool>() ? 0 : 1);
        Shader.SetGlobalFloat("_sunSpread", m_rayTracing.SunSpread.GetValue<float>()+1);

        float pixelSpreadAngle = Mathf.Atan((2*Mathf.Tan((Mathf.Deg2Rad*_camera.fieldOfView)/2f))/_camera.scaledPixelHeight);
        Shader.SetGlobalFloat("surfaceSpreadAngle", pixelSpreadAngle);
    }

    void Render(ref RenderingData renderingData)
    {
        ref var cameraData = ref renderingData.cameraData;
        var w = cameraData.camera.scaledPixelWidth;
        var h = cameraData.camera.scaledPixelHeight;

        var source = currentTarget;
        InitResultTexture(w, h);        

        command.SetRayTracingTextureParam(rayTracingShader, "RenderTarget", resultTexture);
        command.DispatchRays(rayTracingShader, "Raytracer", (uint)w, (uint)h, 1u, cameraData.camera);
        
        command.Blit(resultTexture, source, blendMat, -1);
        //command.Blit(resultTexture, source);
    }
}

