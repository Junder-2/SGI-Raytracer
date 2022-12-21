using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering.Universal;
public class RaytracingRenderPass : ScriptableRenderPass
{
    private string _profilerTag;

    private RTHandle _currentTarget;
    private RenderTexture _resultTexture;
    private readonly RayTracingShader _rayTracingShader;
    private Material _blendMat;

    private LayerMask _updateLayers;

    private static RayTracingAccelerationStructure _accelerationStructure;
    private Raytracing _raytracingVolume;
    private RayTracingInstanceCullingConfig _cullingConfig;

    private CommandBuffer _command;

    private float _frameIndex;

    private bool _init = false;
    
    private static readonly int MaxReflectDepth = Shader.PropertyToID("gMaxReflectDepth");
    private static readonly int MaxIndirectDepth = Shader.PropertyToID("gMaxIndirectDepth");
    private static readonly int MaxRefractionDepth = Shader.PropertyToID("gMaxRefractionDepth");
    private static readonly int RenderShadows = Shader.PropertyToID("gRenderShadows");
    private static readonly int ReflectionMode = Shader.PropertyToID("gReflectionMode");
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
        _rayTracingShader = shader;
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
        
        _command = CommandBufferPool.Get(_profilerTag);
        InitCommandBuffer();
    }

    public void OnDisable()
    {
        _accelerationStructure.Release();
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
        _command.SetRayTracingShaderPass(_rayTracingShader, "MyRaytracingPass");
        _command.SetRayTracingAccelerationStructure(_rayTracingShader, "_RaytracingAccelerationStructure", _accelerationStructure);
        
        _cullingConfig = new RayTracingInstanceCullingConfig
        {
            flags = RayTracingInstanceCullingFlags.EnableLODCulling |
                    RayTracingInstanceCullingFlags.EnableSphereCulling,
            lodParameters = {
                isOrthographic = false, 
                orthoSize = 0
            },
            subMeshFlagsConfig = {
                opaqueMaterials = RayTracingSubMeshFlags.Enabled | RayTracingSubMeshFlags.ClosestHitOnly,
                transparentMaterials = RayTracingSubMeshFlags.Enabled
            },
            triangleCullingConfig = {
                frontTriangleCounterClockwise = false, 
                optionalDoubleSidedShaderKeywords = new []{"DOUBLESIDED"}, 
                forceDoubleSided = _raytracingVolume.ForceDoubleSided.GetValue<bool>()
            },
            transparentMaterialConfig = {
                optionalShaderKeywords = new[] { "USE_ALPHA" }
            }
        };

        var defaultTest = new RayTracingInstanceCullingTest
        {
            allowOpaqueMaterials = true, allowTransparentMaterials = true, layerMask = -1, instanceMask = 1,
            shadowCastingModeMask = (1 << (int)ShadowCastingMode.Off) | (1 << (int)ShadowCastingMode.On) | (1 << (int)ShadowCastingMode.TwoSided),
        };
        var shadowTest = new RayTracingInstanceCullingTest
        {
            allowOpaqueMaterials = true, allowTransparentMaterials = true, layerMask = -1, instanceMask = 2,
            shadowCastingModeMask = (1 << (int)ShadowCastingMode.On) | (1 << (int)ShadowCastingMode.TwoSided) | (1 << (int)ShadowCastingMode.ShadowsOnly)
        };

        _cullingConfig.instanceTests = new[] { defaultTest, shadowTest };
    }

    void UpdateSettingData(ref RenderingData renderingData)
    {
        ref var cameraData = ref renderingData.cameraData;

        var camera = cameraData.camera;
        
        _command.SetRayTracingIntParam(_rayTracingShader, CullBackfaces, _raytracingVolume.ForceDoubleSided.GetValue<bool>() ? 0 : 1);

        float pixelSpreadAngle = Mathf.Atan((2*Mathf.Tan((Mathf.Deg2Rad*camera.fieldOfView)*.5f))/camera.scaledPixelHeight);
        _command.SetRayTracingFloatParam(_rayTracingShader, PixelSpreadAngle, pixelSpreadAngle);

        _command.SetRayTracingVectorParam(_rayTracingShader, BottomSkyColor, _raytracingVolume.floorColor.GetValue<Color>());
        _command.SetRayTracingVectorParam(_rayTracingShader, TopSkyColor, _raytracingVolume.skyColor.GetValue<Color>());
        _command.SetRayTracingFloatParam(_rayTracingShader, IndirectSkyStrength, _raytracingVolume.IndirectSkyStrength.GetValue<float>());
        
        if(RenderSettings.skybox != null && RenderSettings.skybox.HasTexture(Tex) && _raytracingVolume.UseSkybox.GetValue<bool>())
        {
            _command.SetGlobalTexture(GlobalEnvTex, RenderSettings.skybox.GetTexture(Tex));
            _command.SetRayTracingIntParam(_rayTracingShader, UseSkyBox, 1);
        }
        else
        {
            _command.SetRayTracingIntParam(_rayTracingShader, UseSkyBox, 0);
        }
        
        _command.SetGlobalInteger(ClipDistance, (int)camera.farClipPlane);
        _command.SetGlobalInteger(MaxReflectDepth, _raytracingVolume.MaxReflections.GetValue<int>());
        _command.SetGlobalInteger(MaxIndirectDepth, _raytracingVolume.MaxIndirect.GetValue<int>());
        _command.SetGlobalInteger(MaxRefractionDepth, _raytracingVolume.MaxRefractions.GetValue<int>());
        _command.SetGlobalInteger(RenderShadows, _raytracingVolume.RaytracedShadows.GetValue<int>());
        _command.SetGlobalInteger(ReflectionMode, _raytracingVolume.ReflectionMode.GetValue<int>());
        _command.SetGlobalFloat(SunSpread, _raytracingVolume.SunSpread.GetValue<float>()+1);
    }

    void UpdateCameraData(ref RenderingData renderingData)
    {
        ref var cameraData = ref renderingData.cameraData;

        var camera = cameraData.camera;
        
        _command.SetRayTracingMatrixParam(_rayTracingShader, CameraToWorld, camera.cameraToWorldMatrix);
        _command.SetRayTracingMatrixParam(_rayTracingShader, CameraInverseProjection, camera.projectionMatrix.inverse);

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
        _command.SetRayTracingIntParam(_rayTracingShader, FrameIndex, Mathf.FloorToInt(_frameIndex));
    }

    void Render(ref RenderingData renderingData)
    {
        ref var cameraData = ref renderingData.cameraData;
        var w = cameraData.camera.scaledPixelWidth;
        var h = cameraData.camera.scaledPixelHeight;

        var source = _currentTarget;
        InitResultTexture(w, h);        

        _command.SetRayTracingTextureParam(_rayTracingShader, RenderTarget, _resultTexture);
        _command.DispatchRays(_rayTracingShader, "Raytracer", (uint)w, (uint)h, 1u, cameraData.camera);
        
        _command.Blit(_resultTexture, source, _blendMat, -1);
    }
}

