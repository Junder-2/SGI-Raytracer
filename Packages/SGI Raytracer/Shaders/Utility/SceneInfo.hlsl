#include "UnityCG.cginc"

half3 SampleSkybox(half3 worldRefl) 
{
    half4 skyData0 = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, worldRefl, 0);

    return DecodeHDR (skyData0, unity_SpecCube0_HDR);
}