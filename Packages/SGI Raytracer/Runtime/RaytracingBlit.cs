using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.Universal.Internal;

namespace SGI_Raytracer
{
    public class RaytracingBlit : ScriptableRendererFeature
    {
        private RaytracingRenderPass rayTracingPass;

        [Serializable]
        public class RaytracePassSettings
        {
            public RayTracingShader rayTracingShader;
            public LayerMask updateLayers;
            public RenderPassEvent whenToInsert = RenderPassEvent.AfterRenderingSkybox;
        }
    
        public RaytracePassSettings Settings = new();

        public override void Create()
        {
            rayTracingPass = new RaytracingRenderPass("Raytracer", Settings.whenToInsert, Settings.rayTracingShader, Settings.updateLayers);
            
            rayTracingPass.Setup();
        }
    
        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            renderer.EnqueuePass(rayTracingPass);
        }

        public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
        {
           
        }
    }
}
