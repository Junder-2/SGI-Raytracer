using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering.Universal;

public class Raytracing : VolumeComponent, IPostProcessComponent
{
    public BoolParameter Enable = new(false);
    public BoolParameter UseSkybox = new(false);
    public BoolParameter CullBackfaces = new(false);
    public BoolParameter DoubleSidedShadows = new(false);
    public BoolParameter DropShadows = new(false);
    public NoInterpClampedFloatParameter SunSpread = new(0, 0, 10);
    public NoInterpClampedIntParameter MaxReflections = new(0, 0, 8);
    public NoInterpClampedIntParameter MaxIndirect = new(0, 0, 8);
    public NoInterpClampedFloatParameter IndirectSkyStrength = new(1, 0, 2);
    public NoInterpClampedIntParameter MaxRefractions = new(0, 0, 8);
    public NoInterpClampedIntParameter RaytracedShadows = new(0, 0, 4);
    public BoolParameter HalfTraceReflections = new(false);

    public ColorParameter skyColor = new(Color.blue);
    public ColorParameter floorColor = new(Color.gray);

    public bool IsActive() => Enable.value;
    public bool IsTileCompatible() => false;

    public void RetrieveInstances(ref RayTracingAccelerationStructure accelerationStructure)
    {
        foreach (var item in FindObjectsOfType<Renderer>())
        {
            if (item.rayTracingMode == RayTracingMode.Off) continue;
            
            accelerationStructure.AddInstance(item);
            accelerationStructure.UpdateInstanceTransform(item);
        }
    }

    private Matrix4x4 _cameraWorldMatrix;
    public bool UpdateParameters = true;
    public bool UpdateCamera = true;

    private void Update()
    {
        if (_cameraWorldMatrix == Camera.main.transform.localToWorldMatrix) return;
        UpdateCamera = true;
        _cameraWorldMatrix = Camera.main.transform.localToWorldMatrix;
    }
}
