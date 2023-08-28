using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace SGI_Raytracer
{
    public class Raytracing : VolumeComponent, IPostProcessComponent
    {
        public BoolParameter Enable = new(false);
        public BoolParameter UseSkybox = new(false);
        public BoolParameter ForceDoubleSided = new(false);
        public NoInterpClampedFloatParameter SunSpread = new(0, 0, 10);
        public NoInterpClampedIntParameter MaxReflections = new(2, 0, 8);
        public NoInterpClampedIntParameter MaxIndirect = new(0, 0, 8);
        public NoInterpClampedFloatParameter IndirectSkyStrength = new(1, 0, 2);
        public NoInterpClampedIntParameter MaxRefractions = new(2, 0, 8);
        public NoInterpClampedIntParameter ShadowSamples = new(1, 0, 4);
        public NoInterpClampedIntParameter ReflectionMode = new(1, 0, 3);

        public ColorParameter SkyColor = new(Color.blue);
        public ColorParameter FloorColor = new(Color.gray);

        public bool IsActive() => Enable.value;
        public bool IsTileCompatible() => false;
    }
}
