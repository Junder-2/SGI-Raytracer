#pragma shader_feature_local _ USE_ALPHA
#pragma shader_feature_local _ USE_REFLECTIONS 
#pragma shader_feature_local _ USE_NORMALMAP            
#pragma shader_feature_local _ DISABLE_ADDITIONAL_LIGHTS
#pragma shader_feature_local _ UNLIT
					
#include "RayHelpers.cginc"

[shader("anyhit")]
void anyHit (inout RayPayload rayPayload , in AttributeData attributeData)
{
    uint rayFlags = RayFlags();
    
    #ifndef CAST_SHADOWS
        if((rayFlags & SHADOWRAY_FLAG) == SHADOWRAY_FLAG)
            IgnoreHit();
    #endif
        

    #ifdef USE_ALPHA
        IntersectionVertex currentvertex;
        GetCurrentIntersectionVertex(attributeData, currentvertex);
	                        
        half3 worldPos = WorldRayOrigin() + RayTCurrent()* WorldRayDirection();
        float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
        float3 worldNormal = normalize(mul(objectToWorld, currentvertex.normalOS));
        
        float LOD = RayCalcLOD(currentvertex, rayPayload.rayConeWidth, WorldRayDirection(), worldNormal);

        half2 uv = CALCULATEUV;
        
        half alpha = (_Color*SampleTex2D(_MainTex, sampler_MainTex, uv, LOD)).w;

        if(alpha <= _AlphaClip)
            IgnoreHit();
    #endif  
}     

[shader("closesthit")]
void ClosestHit(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes)
{
    float3 debug = 0;

    float3 rayOrigin = WorldRayOrigin();
    float3 rayDir = WorldRayDirection();
    float3 worldPos = rayOrigin + RayTCurrent()* rayDir;
    // compute vertex data on ray/triangle intersection
    IntersectionVertex currentvertex;
    GetCurrentIntersectionVertex(attributeData, currentvertex, rayDir);
    float2 uv = CALCULATEUV;

    float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
    float3 worldNormal = normalize(mul(objectToWorld, currentvertex.normalOS));

    rayPayload.rayConeWidth = rayPayload.rayConeSpreadAngle*RayTCurrent();
            
    float LOD = RayCalcLOD(currentvertex, rayPayload.rayConeWidth, rayDir, worldNormal);

    float4 color = _Color*SampleTex2D(_MainTex, sampler_MainTex, uv, LOD);
    #ifdef USE_ALPHA
        float alpha = color.w*step(_AlphaClip, color.w);
    #else
        float alpha = 1;
    #endif
    color = color*_Intensity;

    float4 specColor = _SpecularColor*SampleTex2D(_SpecularMap, sampler_SpecularMap, uv, LOD).rgba;
    float specularStrength = _SpecularStrength*specColor.a;

    float4 attributes = SampleTex2D(_AttributeMap, sampler_AttributeMap, uv, LOD).rgba;
    float reflectance = _Reflection*attributes.r;

    #ifdef USE_NORMALMAP
        float4 tangentNormal = SampleTex2D(_NormalMap, sampler_NormalMap, uv, LOD);        
                    
        RayCalcNormalMap(tangentNormal, _NormalStrength, currentvertex, worldNormal);
    #endif
    
    #ifdef DOUBLESIDED
        worldNormal *= currentvertex.frontFace ? 1 : -1;
    #endif
		    	
    float3 specular = 0;
    half shadowFactor = 0;
    half3 indirect = _GlossyEnvironmentColor.xyz;
    float3 diffuse = 0;

    float specularLuminance = Luminance(specColor.rgb);

    #ifndef UNLIT
        RayMainLightCalc(worldNormal, worldPos, _SpecularFactor, specularStrength*specularLuminance, rayPayload, shadowFactor, specular, diffuse);
        #ifndef  DISABLE_ADDITIONAL_LIGHTS
            RayAdditionalLightCalc(worldNormal, worldPos, _SpecularFactor, specularStrength*specularLuminance, rayPayload, shadowFactor, specular, diffuse);
        #endif
    #else
        diffuse = 1;
        shadowFactor = 1;
    #endif

    float3 reflectionColor = color.xyz;				

    #ifdef USE_REFLECTIONS
        float3 reflectDir = reflect(rayDir, worldNormal); 
			    
        bool shouldReflect = false;

        if(RayShouldReflect(_Reflection, rayPayload))
            RayReflectionCalc(worldPos, reflectDir, reflectance*specColor.rgb, rayPayload, reflectionColor);                             
    #endif

    if(rayPayload.depth < 1 && gMaxIndirectDepth != 0)
        RayIndirectCalc(worldPos, worldNormal, 1, rayPayload, indirect);

    #ifdef USE_ALPHA
        if(alpha < 1 && rayPayload.depth < gMaxRefractionDepth)
            RayTransparentCalc(alpha, worldPos, worldNormal, _Refraction, rayPayload, color, reflectionColor);
    #endif

    rayPayload.color += float4((lerp(color.xyz, reflectionColor, reflectance)*lerp(1, (diffuse+indirect), alpha)), 1);
    rayPayload.color += float4(specular*specColor.rgb*alpha, 0);
    rayPayload.color *= float4(lerp(1, saturate(shadowFactor+indirect), alpha), 1);

    // stop if we have reached max recursion depth
    if(rayPayload.depth +1 == gMaxDepth)
        return;
}
