#include "Lights.hlsl"

half3 UnpackScaleNormal(half4 packednormal, half bumpScale)
{
	#if defined(UNITY_NO_DXT5nm)
		return packednormal.xyz * 2 - 1;
	#else
		half3 normal;
		normal.xy = (packednormal.wy * 2 - 1);
			normal.xy *= bumpScale;
		normal.z = sqrt(1.0 - saturate(dot(normal.xy, normal.xy)));
		return normal;
	#endif
}

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

void BlinnPhongCalc(half3 lightDir, half3 worldNormal, half3 viewDir, half specularFactor, float specularStrength, inout float3 specular)
{
	float3 halfDir = normalize(lightDir + viewDir);
	half specAngle = max(dot(halfDir, worldNormal), 0.0);
	specular += pow(specAngle, specularFactor)*specularStrength;
}

void MainLightCalc(float3 worldNormal, half3 viewDir, half specularFactor, float specularStrength, inout float shadowFactor, inout float3 specular, inout float3 diffuse)
{
    Light mainLight = GetMainLight();
    half3 lightDir = mainLight.direction;   
    float facing = max(dot(lightDir, worldNormal), 0);  
    float shadowAmount = 1;

    float lightStrength = mainLight.distanceAttenuation*dot(mainLight.color, float3(0.2126, 0.7152, 0.0722));

    if(mainLight.distanceAttenuation >= 0)
    {
        float currLightAmount = 0;
    	
    	currLightAmount = facing*lightStrength;
    	shadowFactor += currLightAmount;

        diffuse += mainLight.color*mainLight.distanceAttenuation;    

        if(facing != 0)
        {
            BlinnPhongCalc(lightDir, worldNormal, viewDir, specularFactor, specularStrength*currLightAmount, specular);
        }
    }
}