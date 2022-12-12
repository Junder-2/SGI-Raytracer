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
    
    private static readonly int MaxReflectDepth = Shader.PropertyToID("_maxReflectDepth");
    private static readonly int MaxIndirectDepth = Shader.PropertyToID("_maxIndirectDepth");
    private static readonly int MaxRefractionDepth = Shader.PropertyToID("_maxRefractionDepth");
    private static readonly int RenderShadows = Shader.PropertyToID("_renderShadows");
    private static readonly int UseDropShadows = Shader.PropertyToID("_useDropShadows");
    private static readonly int CullShadowBackfaces = Shader.PropertyToID("_cullShadowBackfaces");
    private static readonly int HalfTraceReflections = Shader.PropertyToID("_halfTraceReflections");
    private static readonly int SunSpread = Shader.PropertyToID("_sunSpread");
    private static readonly int Tex = Shader.PropertyToID("_Tex");

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
        _raytracingVolume = stack.GetComponent<Raytracing>();
        if (_raytracingVolume == null) return;
        if (!_raytracingVolume.IsActive()) return;
        _raytracingVolume.RetrieveInstances(ref _accelerationStructure);

        _frameIndex = 0;
        _init = true;
        _raytracingVolume.UpdateParameters = true;
        _raytracingVolume.UpdateCamera = true;
    }

    public void Setup(in RTHandle currentTarget)
    {
        this._currentTarget = currentTarget;
    }

    Raytracing _raytracingVolume;

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        if (!renderingData.cameraData.postProcessEnabled) return;
        var stack = VolumeManager.instance.stack;
        _raytracingVolume = stack.GetComponent<Raytracing>();
        if (_raytracingVolume == null) return;
        if (!_raytracingVolume.IsActive()) return;

        if(_accelerationStructure.GetInstanceCount() == 0) _raytracingVolume.RetrieveInstances(ref _accelerationStructure);
        _accelerationStructure.Build();

        _command = CommandBufferPool.Get(_profilerTag);
        if(_init)
            InitCommandBuffer();

        _frameIndex += Time.deltaTime*60f;

        if(_raytracingVolume.UpdateParameters)
            UpdateSettingData(ref renderingData);

        if (_raytracingVolume.UpdateCamera)
            UpdateCameraData(ref renderingData);
        
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

    void UpdateSettingData(ref RenderingData renderingData)
    {
        ref var cameraData = ref renderingData.cameraData;

        var camera = cameraData.camera;
        
        _command.SetRayTracingIntParam(rayTracingShader, "_cullBackfaces", _raytracingVolume.CullBackfaces.GetValue<bool>() ? 1 : 0);

        float pixelSpreadAngle = Mathf.Atan((2*Mathf.Tan((Mathf.Deg2Rad*camera.fieldOfView)*.5f))/camera.scaledPixelHeight);
        _command.SetRayTracingFloatParam(rayTracingShader, "_PixelSpreadAngle", pixelSpreadAngle);
        
        _command.SetRayTracingVectorParam(rayTracingShader, "bottomColor", _raytracingVolume.floorColor.GetValue<Color>());
        _command.SetRayTracingVectorParam(rayTracingShader, "skyColor", _raytracingVolume.skyColor.GetValue<Color>());
        _command.SetRayTracingFloatParam(rayTracingShader, "_IndirectSkyStrength", _raytracingVolume.IndirectSkyStrength.GetValue<float>());
        
        if(RenderSettings.skybox != null && RenderSettings.skybox.HasTexture(Tex) && _raytracingVolume.UseSkybox.GetValue<bool>())
        {
            _command.SetGlobalTexture("g_EnvTex", RenderSettings.skybox.GetTexture(Tex));
            _command.SetRayTracingIntParam(rayTracingShader, "_useSkyBox", 1);
        }
        else
        {
            _command.SetRayTracingIntParam(rayTracingShader, "_useSkyBox", 0);
        }
        
        Shader.SetGlobalInteger(MaxReflectDepth, _raytracingVolume.MaxReflections.GetValue<int>());
        Shader.SetGlobalInteger(MaxIndirectDepth, _raytracingVolume.MaxIndirect.GetValue<int>());
        Shader.SetGlobalInteger(MaxRefractionDepth, _raytracingVolume.MaxRefractions.GetValue<int>());
        Shader.SetGlobalInteger(RenderShadows, _raytracingVolume.RaytracedShadows.GetValue<int>());
        Shader.SetGlobalInteger(UseDropShadows, _raytracingVolume.DropShadows.GetValue<bool>() ? 1 : 0);
        Shader.SetGlobalInteger(HalfTraceReflections, _raytracingVolume.HalfTraceReflections.GetValue<bool>() ? 1 : 0);
        Shader.SetGlobalInteger(CullShadowBackfaces, _raytracingVolume.DoubleSidedShadows.GetValue<bool>() ? 0 : 1);
        Shader.SetGlobalFloat(SunSpread, _raytracingVolume.SunSpread.GetValue<float>()+1);
    }

    void UpdateCameraData(ref RenderingData renderingData)
    {
        ref var cameraData = ref renderingData.cameraData;

        var camera = cameraData.camera;
        
        _command.SetRayTracingMatrixParam(rayTracingShader, "_CameraToWorld", camera.cameraToWorldMatrix);
        _command.SetRayTracingMatrixParam(rayTracingShader, "_CameraInverseProjection", camera.projectionMatrix.inverse);
    }

    void UpdateCommandBuffer(ref RenderingData renderingData)
    {
        _command.SetRayTracingIntParam(rayTracingShader, "_FrameIndex", Mathf.FloorToInt(_frameIndex));
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
    }
}

