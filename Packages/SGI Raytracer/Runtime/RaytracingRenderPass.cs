using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
// ReSharper disable InconsistentNaming

namespace SGI_Raytracer
{
    public class RaytracingRenderPass : ScriptableRenderPass
    {
        private string profilerTag;
        private ProfilingSampler rayProfilingSampler;

        private RTHandle raytraceTarget;
        private RenderTexture resultTexture;
        private RayTracingShader rayTracingShader;

        private LayerMask updateLayers;

        private static RayTracingAccelerationStructure accelerationStructure;
        private Raytracing raytracingVolume;
        private RayTracingInstanceCullingConfig raytraceingCullingConfig;

        private CommandBuffer command;
        private GlobalKeyword raytracingFeature;

        private float frameIndex;

        private static readonly int id_MaxReflectDepth = Shader.PropertyToID("gMaxReflectDepth");
        private static readonly int id_MaxIndirectDepth = Shader.PropertyToID("gMaxIndirectDepth");
        private static readonly int id_MaxRefractionDepth = Shader.PropertyToID("gMaxRefractionDepth");
        private static readonly int id_RenderShadows = Shader.PropertyToID("gRenderShadows");
        private static readonly int id_ReflectionMode = Shader.PropertyToID("gReflectionMode");
        private static readonly int id_NearClip = Shader.PropertyToID("_NearClip");
        private static readonly int id_ClipDistance = Shader.PropertyToID("gClipDistance");
        private static readonly int id_SunSpread = Shader.PropertyToID("gSunSpread");
        private static readonly int id_Tex = Shader.PropertyToID("_Tex");

        private static readonly int id_CullBackfaces = Shader.PropertyToID("_CullBackfaces");
        private static readonly int id_PixelSpreadAngle = Shader.PropertyToID("_PixelSpreadAngle");
        private static readonly int id_BottomSkyColor = Shader.PropertyToID("_BottomSkyColor");
        private static readonly int id_TopSkyColor = Shader.PropertyToID("_TopSkyColor");
        private static readonly int id_IndirectSkyStrength = Shader.PropertyToID("_IndirectSkyStrength");
        private static readonly int id_GlobalEnvTex = Shader.PropertyToID("g_EnvTex");
        private static readonly int id_UseSkyBox = Shader.PropertyToID("_UseSkyBox");
        private static readonly int id_FrameIndex = Shader.PropertyToID("_FrameIndex");
        private static readonly int id_CameraToWorld = Shader.PropertyToID("_CameraToWorld");
        private static readonly int id_CameraInverseProjection = Shader.PropertyToID("_CameraInverseProjection");
        private static readonly int id_RenderTarget = Shader.PropertyToID("_RenderTarget");

        public RaytracingRenderPass(string profilerTag, RenderPassEvent renderPassEvent, RayTracingShader shader, LayerMask mask)
        {
            this.profilerTag = profilerTag;
            rayProfilingSampler = new ProfilingSampler(profilerTag);
            updateLayers = mask;
            rayTracingShader = shader;
            this.renderPassEvent = renderPassEvent;

            var settings = new RayTracingAccelerationStructure.RASSettings
            {
                layerMask = updateLayers,
                managementMode = RayTracingAccelerationStructure.ManagementMode.Manual,
                rayTracingModeMask = RayTracingAccelerationStructure.RayTracingModeMask.Everything
            };
            accelerationStructure = new RayTracingAccelerationStructure(settings);
            
            var stack = VolumeManager.instance.stack;
            raytracingVolume = stack.GetComponent<Raytracing>();
            if (raytracingVolume == null) return;
            if (!raytracingVolume.IsActive()) return;

            frameIndex = 0;
        }

        public void Setup()
        {
            command = CommandBufferPool.Get(this.profilerTag);
            CreateConfig();
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            using (new ProfilingScope(command, rayProfilingSampler))
            {
                var colorDesc = renderingData.cameraData.cameraTargetDescriptor;
                colorDesc.depthBufferBits = 0;
                colorDesc.enableRandomWrite = true;
                // Set up temporary color buffer (for blit)
                RenderingUtils.ReAllocateIfNeeded(ref raytraceTarget, colorDesc, name: "_RaytraceTexture");
                
                frameIndex += Time.deltaTime*60f;
                UpdateCameraData(cmd, ref renderingData);
                UpdateSettingData(ref renderingData);
                UpdateCulling(ref renderingData);
            }

            cullUpdate += Time.deltaTime;
            
            if(cullUpdate < 0.033f) return;

            cullUpdate = 0;
            
            accelerationStructure.ClearInstances();
            accelerationStructure.CullInstances(ref raytraceingCullingConfig);
            accelerationStructure.Build();
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            base.Configure(cmd, cameraTextureDescriptor);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (!renderingData.cameraData.postProcessEnabled) return;
            var stack = VolumeManager.instance.stack;
            raytracingVolume = stack.GetComponent<Raytracing>();
            if (raytracingVolume == null) return;
            if (!raytracingVolume.IsActive())
                return;

            command = CommandBufferPool.Get(profilerTag);

            using (new ProfilingScope(command, rayProfilingSampler))
            {
                context.ExecuteCommandBuffer(command);
                command.Clear();

                Render(ref renderingData);
                Shader.EnableKeyword(raytracingFeature);
            }
            context.ExecuteCommandBuffer(command);
            command.Clear();
            CommandBufferPool.Release(command);
        }

        public override void OnFinishCameraStackRendering(CommandBuffer cmd) => cmd.DisableKeyword(raytracingFeature);

        private void CreateConfig()
        {
            //Debug.Log("creating config");
            raytracingFeature = GlobalKeyword.Create("RAYTRACING_ON");

            raytraceingCullingConfig = new RayTracingInstanceCullingConfig
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
                    forceDoubleSided = raytracingVolume.ForceDoubleSided.GetValue<bool>()
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

            raytraceingCullingConfig.instanceTests = new[] { defaultTest, shadowTest };

            cullUpdate = 50;
            
            accelerationStructure.ClearInstances();
            accelerationStructure.CullInstances(ref raytraceingCullingConfig);
            accelerationStructure.Build();
        }

        private void UpdateSettingData(ref RenderingData renderingData)
        {
            ref var cameraData = ref renderingData.cameraData;
            var camera = cameraData.camera;
        
            command.SetRayTracingIntParam(rayTracingShader, id_CullBackfaces, raytracingVolume.ForceDoubleSided.GetValue<bool>() ? 0 : 1);

            float pixelSpreadAngle = Mathf.Atan((2*Mathf.Tan((Mathf.Deg2Rad*camera.fieldOfView)*.5f))/camera.scaledPixelHeight);
            command.SetRayTracingFloatParam(rayTracingShader, id_PixelSpreadAngle, pixelSpreadAngle);

            command.SetRayTracingVectorParam(rayTracingShader, id_BottomSkyColor, raytracingVolume.FloorColor.GetValue<Color>());
            command.SetRayTracingVectorParam(rayTracingShader, id_TopSkyColor, raytracingVolume.SkyColor.GetValue<Color>());
            command.SetRayTracingFloatParam(rayTracingShader, id_IndirectSkyStrength, raytracingVolume.IndirectSkyStrength.GetValue<float>());
        
            if(RenderSettings.skybox != null && RenderSettings.skybox.HasTexture(id_Tex) && raytracingVolume.UseSkybox.GetValue<bool>())
            {
                command.SetGlobalTexture(id_GlobalEnvTex, RenderSettings.skybox.GetTexture(id_Tex));
                command.SetRayTracingIntParam(rayTracingShader, id_UseSkyBox, 1);
            }
            else
            {
                command.SetRayTracingIntParam(rayTracingShader, id_UseSkyBox, 0);
            }
            
            command.SetGlobalInteger(id_ClipDistance, (int)camera.farClipPlane);
            command.SetGlobalInteger(id_MaxReflectDepth, raytracingVolume.MaxReflections.GetValue<int>());
            command.SetGlobalInteger(id_MaxIndirectDepth, raytracingVolume.MaxIndirect.GetValue<int>());
            command.SetGlobalInteger(id_MaxRefractionDepth, raytracingVolume.MaxRefractions.GetValue<int>());
            command.SetGlobalInteger(id_RenderShadows, raytracingVolume.ShadowSamples.GetValue<int>());
            command.SetGlobalInteger(id_ReflectionMode, raytracingVolume.ReflectionMode.GetValue<int>());
            command.SetGlobalFloat(id_SunSpread, raytracingVolume.SunSpread.GetValue<float>()+1);
        }

        private float cullUpdate = 0f;

        private void UpdateCameraData(CommandBuffer cmd, ref RenderingData renderingData)
        {
            ref var cameraData = ref renderingData.cameraData;

            var camera = cameraData.camera;
            
            cmd.SetRayTracingIntParam(rayTracingShader, id_FrameIndex, Mathf.FloorToInt(frameIndex));
            cmd.SetRayTracingFloatParam(rayTracingShader, id_NearClip, camera.nearClipPlane);
            cmd.SetRayTracingMatrixParam(rayTracingShader, id_CameraToWorld, camera.cameraToWorldMatrix);
            cmd.SetRayTracingMatrixParam(rayTracingShader, id_CameraInverseProjection, camera.projectionMatrix.inverse);
        }

        private void UpdateCulling(ref RenderingData renderingData)
        {
            ref var cameraData = ref renderingData.cameraData;
            var camera = cameraData.camera;
            
            raytraceingCullingConfig.sphereRadius = camera.farClipPlane*.5f;
            raytraceingCullingConfig.sphereCenter = cameraData.worldSpaceCameraPos;
            raytraceingCullingConfig.lodParameters.fieldOfView = camera.fieldOfView;
            raytraceingCullingConfig.lodParameters.cameraPosition = cameraData.worldSpaceCameraPos;
            raytraceingCullingConfig.lodParameters.cameraPixelHeight = camera.pixelHeight;

            accelerationStructure.ClearInstances();
            accelerationStructure.CullInstances(ref raytraceingCullingConfig);
            accelerationStructure.Build();
        }

        private void Render(ref RenderingData renderingData)
        {
            ref var cameraData = ref renderingData.cameraData;
            var w = cameraData.camera.scaledPixelWidth;
            var h = cameraData.camera.scaledPixelHeight;
            
            command.SetRayTracingShaderPass(rayTracingShader, "MyRaytracingPass");
            command.SetRayTracingAccelerationStructure(rayTracingShader, "_RaytracingAccelerationStructure", accelerationStructure);

            var camTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
            command.SetRayTracingTextureParam(rayTracingShader, id_RenderTarget, raytraceTarget);
            command.DispatchRays(rayTracingShader, "Raytracer", (uint)w, (uint)h, 1u, cameraData.camera);
        
            Blitter.BlitCameraTexture(command, raytraceTarget, camTarget);
        }
        
        public void Dispose() {
            raytraceTarget?.Release();
        }
    }
}
