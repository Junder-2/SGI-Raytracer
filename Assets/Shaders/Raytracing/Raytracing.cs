using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering.Universal;

public class Raytracing : VolumeComponent, IPostProcessComponent
{
    public BoolParameter Enable = new BoolParameter(false);
    public BoolParameter UseSkybox = new BoolParameter(false);
    public BoolParameter CullBackfaces = new BoolParameter(false);
    public BoolParameter DoubleSidedShadows = new BoolParameter(false);
    public BoolParameter DropShadows = new BoolParameter(false);
    public NoInterpClampedFloatParameter SunSpread = new NoInterpClampedFloatParameter(0, 0, 10);
    public NoInterpClampedIntParameter MaxReflections = new NoInterpClampedIntParameter(0, 0, 8);
    public NoInterpClampedIntParameter MaxIndirect = new NoInterpClampedIntParameter(0, 0, 8);
    public NoInterpClampedFloatParameter IndirectSkyStrength = new NoInterpClampedFloatParameter(1, 0, 2);
    public NoInterpClampedIntParameter MaxRefractions = new NoInterpClampedIntParameter(0, 0, 8);
    public NoInterpClampedIntParameter RaytracedShadows = new NoInterpClampedIntParameter(0, 0, 4);
    public BoolParameter HalfTraceReflections = new BoolParameter(false);

    public ColorParameter skyColor = new ColorParameter(Color.blue);
    public ColorParameter floorColor = new ColorParameter(Color.gray);

    public bool IsActive()
    {
        return Enable.value;
    }

    public bool IsTileCompatible() => false;

    private void Start() 
    {
        UpdateParameters = false;
    }

    public void RetrieveInstances(ref RayTracingAccelerationStructure accelerationStructure)
    {
        foreach (var item in FindObjectsOfType<Renderer>())
        {
            if(item.rayTracingMode != RayTracingMode.Off)
            {
                accelerationStructure.AddInstance(item);
                accelerationStructure.UpdateInstanceTransform(item);
            }
        }
    }

    private Matrix4x4 _cameraWorldMatrix;
    public bool UpdateParameters = true;

    private void Update() 
    {
        if(_cameraWorldMatrix != Camera.main.transform.localToWorldMatrix)
		{
			UpdateParameters = true;
            _cameraWorldMatrix = Camera.main.transform.localToWorldMatrix;
		}    
    }
}
