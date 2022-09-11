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
        // we're free to put whatever we want here, public fields will be exposed in the inspector
        public bool IsEnabled = true;
        public RayTracingShader rayTracingShader;
        public Shader Colorblit;
        public LayerMask updateLayers;
        public RenderPassEvent WhenToInsert = RenderPassEvent.AfterRendering;
    }

    // MUST be named "settings" (lowercase) to be shown in the Render Features inspector
    public MyFeatureSettings settings = new MyFeatureSettings();

    public override void Create()
    {
        Material colorBlit = null;
        if(settings.Colorblit != null)
            colorBlit = new Material(settings.Colorblit);
        rayTracingPass = new RaytracingRenderPass("Raytracer", settings.WhenToInsert, settings.rayTracingShader, colorBlit, settings.updateLayers);
    }
    
    // called every frame once per camera
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (!settings.IsEnabled)
        {   
            // we can do nothing this frame if we want
            return;
        }

        renderer.EnqueuePass(rayTracingPass);
    }

    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        rayTracingPass.Setup(renderer.cameraColorTargetHandle);
    }
}
