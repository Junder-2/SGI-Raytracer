using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering.Universal;

public class RaytracingBlit : ScriptableRendererFeature
{
    RaytracingRenderPass _rayTracingPass;

    [Serializable]
    public class MyFeatureSettings
    {
        public RayTracingShader rayTracingShader;
        public LayerMask updateLayers;
        public RenderPassEvent whenToInsert = RenderPassEvent.AfterRendering;
    }
    
    public MyFeatureSettings settings = new();

    public override void Create()
    {
        _rayTracingPass = new RaytracingRenderPass("Raytracer", settings.whenToInsert, settings.rayTracingShader, settings.updateLayers);
    }
    
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(_rayTracingPass);
    }

    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        _rayTracingPass.Setup(renderer.cameraColorTargetHandle);
    }
}
