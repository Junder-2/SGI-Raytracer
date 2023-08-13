#include "UnityShaderVariables.cginc"
#include "HLSLSupport.cginc"

// Decodes HDR textures
// handles dLDR, RGBM formats
inline half3 DecodeHDR (half4 data, half4 decodeInstructions)
{
    // Take into account texture alpha if decodeInstructions.w is true(the alpha value affects the RGB channels)
    half alpha = decodeInstructions.w * (data.a - 1.0) + 1.0;

    // If Linear mode is not supported we can skip exponent part
    #if defined(UNITY_COLORSPACE_GAMMA)
        return (decodeInstructions.x * alpha) * data.rgb;
    #else
    #   if defined(UNITY_USE_NATIVE_HDR)
            return decodeInstructions.x * data.rgb; // Multiplier for future HDRI relative to absolute conversion.
    #   else
            return (decodeInstructions.x * pow(alpha, decodeInstructions.y)) * data.rgb;
    #   endif
    #endif
}

half3 SampleSkybox(half3 dir)
{
    half4 skyData = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, dir, 0);
    half3 skyColor = DecodeHDR (skyData, unity_SpecCube0_HDR);

    return skyColor;
}