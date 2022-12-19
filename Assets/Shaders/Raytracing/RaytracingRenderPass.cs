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
    Raytracing _raytracingVolume;
    private RayTracingInstanceCullingConfig _cullingConfig;

    private CommandBuffer _command;

    float _frameIndex;

    bool _init = false;
    
    private static readonly int MaxReflectDepth = Shader.PropertyToID("gMaxReflectDepth");
    private static readonly int MaxIndirectDepth = Shader.PropertyToID("gMaxIndirectDepth");
    private static readonly int MaxRefractionDepth = Shader.PropertyToID("gMaxRefractionDepth");
    private static readonly int RenderShadows = Shader.PropertyToID("gRenderShadows");
    private static readonly int UseDropShadows = Shader.PropertyToID("gUseDropShadows");
    private static readonly int CullShadowBackfaces = Shader.PropertyToID("gCullShadowBackfaces");
    private static readonly int HalfTraceReflections = Shader.PropertyToID("gHalfTraceReflections");
    private static readonly int ClipDistance = Shader.PropertyToID("gClipDistance");
    private static readonly int SunSpread = Shader.PropertyToID("gSunSpread");
    private static readonly int Tex = Shader.PropertyToID("_Tex");

    private static readonly int CullBackfaces = Shader.PropertyToID("_CullBackfaces");
    private static readonly int PixelSpreadAngle = Shader.PropertyToID("_PixelSpreadAngle");
    private static readonly int BottomSkyColor = Shader.PropertyToID("_BottomSkyColor");
    private static readonly int TopSkyColor = Shader.PropertyToID("_TopSkyColor");
    private static readonly int IndirectSkyStrength = Shader.PropertyToID("_IndirectSkyStrength");
    private static readonly int GlobalEnvTex = Shader.PropertyToID("g_EnvTex");
    private static readonly int UseSkyBox = Shader.PropertyToID("_UseSkyBox");
    private static readonly int FrameIndex = Shader.PropertyToID("_FrameIndex");
    private static readonly int CameraToWorld = Shader.PropertyToID("_CameraToWorld");
    private static readonly int CameraInverseProjection = Shader.PropertyToID("_CameraInverseProjection");
    private static readonly int RenderTarget = Shader.PropertyToID("_RenderTarget");
    
    
    public RaytracingRenderPass(string profilerTag, RenderPassEvent renderPassEvent, RayTracingShader shader, Material blendMat, LayerMask mask)
    {
        this._profilerTag = profilerTag;
        _updateLayers = mask;
        rayTracingShader = shader;
        this.renderPassEvent = renderPassEvent;
        this._blendMat = blendMat;

        var settings = new RayTracingAccelerationStructure.RASSettings();
        settings.layerMask = _updateLayers;
        settings.managementMode = RayTracingAccelerationStructure.ManagementMode.Manual;
        settings.rayTracingModeMask = RayTracingAccelerationStructure.RayTracingModeMask.Everything;
        
        _accelerationStructure = new RayTracingAccelerationStructure(settings);
        var stack = VolumeManager.instance.stack;
        _raytracingVolume = stack.GetComponent<Raytracing>();
        if (_raytracingVolume == null) return;
        if (!_raytracingVolume.IsActive()) return;

        _frameIndex = 0;
        _init = true;
        _raytracingVolume.UpdateParameters = true;
        _raytracingVolume.UpdateCamera = true;
    }

    public void Setup(in RTHandle currentTarget)
    {
        this._currentTarget = currentTarget;
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        if (!renderingData.cameraData.postProcessEnabled) return;
        var stack = VolumeManager.instance.stack;
        _raytracingVolume = stack.GetComponent<Raytracing>();
        if (_raytracingVolume == null) return;
        if (!_raytracingVolume.IsActive()) return;

        _command = CommandBufferPool.Get(_profilerTag);
        if(_init)
            InitCommandBuffer();

        _frameIndex += Time.deltaTime*60f;

        if(_raytracingVolume.UpdateParameters)
            UpdateSettingData(ref renderingData);
        
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
        
        _cullingConfig = new RayTracingInstanceCullingConfig();

        _cullingConfig.flags = RayTracingInstanceCullingFlags.EnableLODCulling |
                               RayTracingInstanceCullingFlags.EnableSphereCulling;

        _cullingConfig.lodParameters.isOrthographic = false;
        
        _cullingConfig.lodParameters.orthoSize = 0;
        
        _cullingConfig.subMeshFlagsConfig.opaqueMaterials = RayTracingSubMeshFlags.Enabled | RayTracingSubMeshFlags.ClosestHitOnly;
        _cullingConfig.subMeshFlagsConfig.transparentMaterials = RayTracingSubMeshFlags.Enabled;

        _cullingConfig.triangleCullingConfig.frontTriangleCounterClockwise = false;
        _cullingConfig.triangleCullingConfig.optionalDoubleSidedShaderKeywords = new []{"DOUBLESIDED"};
        _cullingConfig.triangleCullingConfig.forceDoubleSided = false;

        _cullingConfig.transparentMaterialConfig.optionalShaderKeywords = new[] { "USE_ALPHA" };

        RayTracingInstanceCullingTest instanceTest = new RayTracingInstanceCullingTest();
        instanceTest.allowOpaqueMaterials = true;
        instanceTest.allowTransparentMaterials = true;
        instanceTest.allowAlphaTestedMaterials = true;
        instanceTest.layerMask = -1;
        instanceTest.shadowCastingModeMask = (1 << (int)ShadowCastingMode.Off) | (1 << (int)ShadowCastingMode.On) | (1 << (int)ShadowCastingMode.TwoSided);
        instanceTest.instanceMask = 1 << 0;

        _cullingConfig.instanceTests = new[] { instanceTest };
    }

    void UpdateSettingData(ref RenderingData renderingData)
    {
        ref var cameraData = ref renderingData.cameraData;

        var camera = cameraData.camera;
        
        _command.SetRayTracingIntParam(rayTracingShader, CullBackfaces, _raytracingVolume.CullBackfaces.GetValue<bool>() ? 1 : 0);

        float pixelSpreadAngle = Mathf.Atan((2*Mathf.Tan((Mathf.Deg2Rad*camera.fieldOfView)*.5f))/camera.scaledPixelHeight);
        _command.SetRayTracingFloatParam(rayTracingShader, PixelSpreadAngle, pixelSpreadAngle);

        _command.SetRayTracingVectorParam(rayTracingShader, BottomSkyColor, _raytracingVolume.floorColor.GetValue<Color>());
        _command.SetRayTracingVectorParam(rayTracingShader, TopSkyColor, _raytracingVolume.skyColor.GetValue<Color>());
        _command.SetRayTracingFloatParam(rayTracingShader, IndirectSkyStrength, _raytracingVolume.IndirectSkyStrength.GetValue<float>());
        
        if(RenderSettings.skybox != null && RenderSettings.skybox.HasTexture(Tex) && _raytracingVolume.UseSkybox.GetValue<bool>())
        {
            _command.SetGlobalTexture(GlobalEnvTex, RenderSettings.skybox.GetTexture(Tex));
            _command.SetRayTracingIntParam(rayTracingShader, UseSkyBox, 1);
        }
        else
        {
            _command.SetRayTracingIntParam(rayTracingShader, UseSkyBox, 0);
        }
        
        _command.SetGlobalInteger(ClipDistance, (int)camera.farClipPlane);
        _command.SetGlobalInteger(MaxReflectDepth, _raytracingVolume.MaxReflections.GetValue<int>());
        _command.SetGlobalInteger(MaxIndirectDepth, _raytracingVolume.MaxIndirect.GetValue<int>());
        _command.SetGlobalInteger(MaxRefractionDepth, _raytracingVolume.MaxRefractions.GetValue<int>());
        _command.SetGlobalInteger(RenderShadows, _raytracingVolume.RaytracedShadows.GetValue<int>());
        _command.SetGlobalInteger(UseDropShadows, _raytracingVolume.DropShadows.GetValue<bool>() ? 1 : 0);
        _command.SetGlobalInteger(HalfTraceReflections, _raytracingVolume.HalfTraceReflections.GetValue<bool>() ? 1 : 0);
        _command.SetGlobalInteger(CullShadowBackfaces, _raytracingVolume.DoubleSidedShadows.GetValue<bool>() ? 0 : 1);
        _command.SetGlobalFloat(SunSpread, _raytracingVolume.SunSpread.GetValue<float>()+1);
    }

    void UpdateCameraData(ref RenderingData renderingData)
    {
        ref var cameraData = ref renderingData.cameraData;

        var camera = cameraData.camera;
        
        _command.SetRayTracingMatrixParam(rayTracingShader, CameraToWorld, camera.cameraToWorldMatrix);
        _command.SetRayTracingMatrixParam(rayTracingShader, CameraInverseProjection, camera.projectionMatrix.inverse);

        /*Vector3 forward = camera.cameraToWorldMatrix.MultiplyVector(Vector3.forward);
        
        _cullingConfig.planes = new[] { new Plane(forward, camera.nearClipPlane), new Plane(forward, camera.farClipPlane)};*/
        _cullingConfig.sphereRadius = camera.farClipPlane*.5f;
        _cullingConfig.sphereCenter = cameraData.worldSpaceCameraPos;
        _cullingConfig.lodParameters.fieldOfView = camera.fieldOfView;
        _cullingConfig.lodParameters.cameraPosition = cameraData.worldSpaceCameraPos;
        _cullingConfig.lodParameters.cameraPixelHeight = camera.pixelHeight;

        _accelerationStructure.ClearInstances();
        _accelerationStructure.CullInstances(ref _cullingConfig);
        _accelerationStructure.Build();
    }

    void UpdateCommandBuffer(ref RenderingData renderingData)
    {
        _command.SetRayTracingIntParam(rayTracingShader, FrameIndex, Mathf.FloorToInt(_frameIndex));
    }

    void Render(ref RenderingData renderingData)
    {
        ref var cameraData = ref renderingData.cameraData;
        var w = cameraData.camera.scaledPixelWidth;
        var h = cameraData.camera.scaledPixelHeight;

        var source = _currentTarget;
        InitResultTexture(w, h);        

        _command.SetRayTracingTextureParam(rayTracingShader, RenderTarget, _resultTexture);
        _command.DispatchRays(rayTracingShader, "Raytracer", (uint)w, (uint)h, 1u, cameraData.camera);
        
        _command.Blit(_resultTexture, source, _blendMat, -1);
    }
}

