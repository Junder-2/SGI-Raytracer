using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering.Universal;
public class RaytracingRenderPass : ScriptableRenderPass
{
    private string _profilerTag;

    private RTHandle _currentTarget;
    private RenderTexture _resultTexture;
    private readonly RayTracingShader rayTracingShader;
    private Material _blendMat;

    LayerMask _updateLayers;

    private static RayTracingAccelerationStructure _accelerationStructure;

    private CommandBuffer _command;

    float _frameIndex;

    bool _init = false;

    public RaytracingRenderPass(string profilerTag, RenderPassEvent renderPassEvent, RayTracingShader shader, Material blendMat, LayerMask mask)
    {
        this._profilerTag = profilerTag;
        _updateLayers = mask;
        rayTracingShader = shader;
        this.renderPassEvent = renderPassEvent;
        this._blendMat = blendMat;

        var settings = new RayTracingAccelerationStructure.RASSettings();
        settings.layerMask = _updateLayers;
        settings.managementMode = RayTracingAccelerationStructure.ManagementMode.Automatic;
        settings.rayTracingModeMask = RayTracingAccelerationStructure.RayTracingModeMask.Everything;

        _accelerationStructure = new RayTracingAccelerationStructure(settings);
        var stack = VolumeManager.instance.stack;
        m_rayTracing = stack.GetComponent<Raytracing>();
        if (m_rayTracing == null) return;
        if (!m_rayTracing.IsActive()) return;
        m_rayTracing.RetrieveInstances(ref _accelerationStructure);

        _frameIndex = 0;
        _init = true;
    }

    public void Setup(in RTHandle currentTarget)
    {
        this._currentTarget = currentTarget;
    }

    Raytracing m_rayTracing;

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        if (!renderingData.cameraData.postProcessEnabled) return;
        var stack = VolumeManager.instance.stack;
        m_rayTracing = stack.GetComponent<Raytracing>();
        if (m_rayTracing == null) return;
        if (!m_rayTracing.IsActive()) return;

        if(_accelerationStructure.GetInstanceCount() == 0) m_rayTracing.RetrieveInstances(ref _accelerationStructure);
        _accelerationStructure.Build();

        _command = CommandBufferPool.Get(_profilerTag);
        if(_init)
            InitCommandBuffer();

        _frameIndex += Time.deltaTime*60f;

        if(m_rayTracing.UpdateParameters)
            UpdateCommandBuffer(ref renderingData);
        Render(ref renderingData);
        context.ExecuteCommandBuffer(_command);
        CommandBufferPool.Release(_command);
    }

    void InitResultTexture(int width, int height)
    {
        if (_resultTexture == null || _resultTexture.width != width || _resultTexture.height != height)
        {
            if (_resultTexture != null)
                _resultTexture.Release();

            _resultTexture = new RenderTexture(width, height, 0, RenderTextureFormat.DefaultHDR, RenderTextureReadWrite.Linear);
            _resultTexture.enableRandomWrite = true;
            _resultTexture.Create();     

            InitCommandBuffer();
        }
    }

    void InitCommandBuffer()
    {        
        _command.SetRayTracingShaderPass(rayTracingShader, "MyRaytracingPass");
        _command.SetRayTracingAccelerationStructure(rayTracingShader, "_RaytracingAccelerationStructure", _accelerationStructure);
    }

    void UpdateCommandBuffer(ref RenderingData renderingData)
    {
        ref var cameraData = ref renderingData.cameraData;

        var camera = cameraData.camera;
        
        _command.SetRayTracingIntParam(rayTracingShader, "_cullBackfaces", m_rayTracing.CullBackfaces.GetValue<bool>() ? 1 : 0);
        
        _command.SetRayTracingMatrixParam(rayTracingShader, "_CameraToWorld", camera.cameraToWorldMatrix);
        _command.SetRayTracingMatrixParam(rayTracingShader, "_CameraInverseProjection", camera.projectionMatrix.inverse);

        _command.SetRayTracingIntParam(rayTracingShader, "_FrameIndex", Mathf.FloorToInt(_frameIndex));
        _command.SetRayTracingVectorParam(rayTracingShader, "bottomColor", m_rayTracing.floorColor.GetValue<Color>());
        _command.SetRayTracingVectorParam(rayTracingShader, "skyColor", m_rayTracing.skyColor.GetValue<Color>());
        _command.SetRayTracingFloatParam(rayTracingShader, "_IndirectSkyStrength", m_rayTracing.IndirectSkyStrength.GetValue<float>());

        if(RenderSettings.skybox != null && RenderSettings.skybox.HasTexture("_Tex") && m_rayTracing.UseSkybox.GetValue<bool>())
        {
            _command.SetGlobalTexture("g_EnvTex", RenderSettings.skybox.GetTexture("_Tex"));
            _command.SetRayTracingIntParam(rayTracingShader, "_useSkyBox", 1);
        }
        else
        {
            _command.SetRayTracingIntParam(rayTracingShader, "_useSkyBox", 0);
        }
        

        Shader.SetGlobalInteger("_maxReflectDepth", m_rayTracing.MaxReflections.GetValue<int>());
        Shader.SetGlobalInteger("_maxIndirectDepth", m_rayTracing.MaxIndirect.GetValue<int>());
        Shader.SetGlobalInteger("_maxRefractionDepth", m_rayTracing.MaxRefractions.GetValue<int>());
        Shader.SetGlobalInteger("_renderShadows", m_rayTracing.RaytracedShadows.GetValue<int>());
        Shader.SetGlobalInteger("_useDropShadows", m_rayTracing.DropShadows.GetValue<bool>() ? 1 : 0);
        Shader.SetGlobalInteger("_halfTraceReflections", m_rayTracing.HalfTraceReflections.GetValue<bool>() ? 1 : 0);
        Shader.SetGlobalInteger("_cullShadowBackfaces", m_rayTracing.DoubleSidedShadows.GetValue<bool>() ? 0 : 1);
        Shader.SetGlobalFloat("_sunSpread", m_rayTracing.SunSpread.GetValue<float>()+1);

        float pixelSpreadAngle = Mathf.Atan((2*Mathf.Tan((Mathf.Deg2Rad*camera.fieldOfView)/2f))/camera.scaledPixelHeight);
        Shader.SetGlobalFloat("surfaceSpreadAngle", pixelSpreadAngle);
    }

    void Render(ref RenderingData renderingData)
    {
        ref var cameraData = ref renderingData.cameraData;
        var w = cameraData.camera.scaledPixelWidth;
        var h = cameraData.camera.scaledPixelHeight;

        var source = _currentTarget;
        InitResultTexture(w, h);        

        _command.SetRayTracingTextureParam(rayTracingShader, "RenderTarget", _resultTexture);
        _command.DispatchRays(rayTracingShader, "Raytracer", (uint)w, (uint)h, 1u, cameraData.camera);
        
        _command.Blit(_resultTexture, source, _blendMat, -1);
        //command.Blit(resultTexture, source);
    }
}

