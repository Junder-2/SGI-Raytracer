using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering.Universal;

namespace SGI_Raytracer
{
    public class RaytracingBlit : ScriptableRendererFeature
    {
        private RaytracingRenderPass rayTracingPass;

        [Serializable]
        public class MyFeatureSettings
        {
            public RayTracingShader rayTracingShader;
            public LayerMask updateLayers;
            public RenderPassEvent whenToInsert = RenderPassEvent.AfterRenderingSkybox;
        }
    
        public MyFeatureSettings Settings = new();

        public override void Create()
        {
            rayTracingPass = new RaytracingRenderPass("Raytracer", Settings.whenToInsert, Settings.rayTracingShader, Settings.updateLayers);
        }
    
        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            renderer.EnqueuePass(rayTracingPass);
        }

        public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
        {
            rayTracingPass.Setup(renderer.cameraColorTargetHandle);
        }
    }
}
