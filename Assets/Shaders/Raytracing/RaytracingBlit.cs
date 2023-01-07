using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering.Universal;

public class RaytracingBlit : ScriptableRendererFeature
{
    RaytracingRenderPass rayTracingPass;

    [System.Serializable]
    public class MyFeatureSettings
    {
        public bool IsEnabled = true;
        public RayTracingShader rayTracingShader;
        public Shader Colorblit;
        public LayerMask updateLayers;
        public RenderPassEvent WhenToInsert = RenderPassEvent.AfterRendering;
    }
    
    public MyFeatureSettings settings = new MyFeatureSettings();

    public override void Create()
    {
        Material colorBlit = null;
        if(settings.Colorblit != null)
            colorBlit = new Material(settings.Colorblit);
        rayTracingPass = new RaytracingRenderPass("Raytracer", settings.WhenToInsert, settings.rayTracingShader, colorBlit, settings.updateLayers);
        
        
    }
    
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (!settings.IsEnabled) return;
        
        renderer.EnqueuePass(rayTracingPass);
    }

    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        rayTracingPass.Setup(renderer.cameraColorTargetHandle);
    }

    private void OnDisable()
    {
        rayTracingPass.OnDisable();
    }
}
