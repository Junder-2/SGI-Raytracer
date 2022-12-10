#pragma shader_feature_local _ USE_ALPHA
#pragma shader_feature_local _ USE_REFLECTIONS 
#pragma shader_feature_local _ USE_NORMALMAP            
#pragma shader_feature_local _ DISABLE_ADDITIONAL_LIGHTS
#pragma shader_feature_local _ CAST_DROP_SHADOW
#pragma shader_feature_local _ UNLIT
					
#include "RayHelpers.cginc"

[shader("anyhit")]
void anyHit (inout RayPayload rayPayload , AttributeData attributeData)
{
    #ifndef CAST_DROP_SHADOW
    uint rayFlags = RayFlags();

    if((rayFlags & DROPSHADOW_FLAG) == DROPSHADOW_FLAG)
        IgnoreHit();
    #endif

    #ifdef USE_ALPHA
    IntersectionVertex currentvertex;
    GetCurrentIntersectionVertex(attributeData, currentvertex);
	                    
    half3 worldPos = WorldRayOrigin() + RayTCurrent()* WorldRayDirection();     
    half dist = distance(WorldRayOrigin(), worldPos);

    half pixelHeight = 0; half pixelWidth = 0;
    _MainTex.GetDimensions(pixelWidth, pixelHeight);
    pixelWidth *= _MainTex_ST.x;
    pixelHeight *= _MainTex_ST.y;
	                    
    half LOD = log2((currentvertex.texCoord0Area*pixelWidth*pixelHeight)/currentvertex.triangleArea)*.5;
    LOD += log2 (abs(rayPayload.rayConeWidth));
    LOD += 0.5 * log2 (pixelWidth * pixelHeight);

    LOD = max(log2(LOD)-LODbias, 0);

    half2 uv = TRANSFORM_TEX(currentvertex.texCoord0, _MainTex);
    if(_ScrollSpeed != 0)
    {
        uv.x += _ScrollSpeed*_Time*.1f*normalize(_ScrollDir).x;
        uv.y += _ScrollSpeed*_Time*.1f*normalize(_ScrollDir).y;
    }
    half alpha = (_Color*_MainTex.SampleLevel(sampler_MainTex, uv, LOD)).w;

    if(alpha <= _AlphaClip)
        IgnoreHit();
    #endif  
}     

[shader("closesthit")]
void ClosestHit(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes)
{
    float3 debug = 0;

    // compute vertex data on ray/triangle intersection
    IntersectionVertex currentvertex;
    GetCurrentIntersectionVertex(attributeData, currentvertex);

    float2 uv = TRANSFORM_TEX(currentvertex.texCoord0, _MainTex);
    if(_ScrollSpeed != 0)
    {
        uv.x += _ScrollSpeed*_Time*.1f*normalize(_ScrollDir).x;
        uv.y += _ScrollSpeed*_Time*.1f*normalize(_ScrollDir).y;
    }   

    float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
    float3 worldNormal = normalize(mul(objectToWorld, currentvertex.normalOS));

    float3 rayOrigin = WorldRayOrigin();
    float3 rayDir = WorldRayDirection();
    float3 worldPos = rayOrigin + RayTCurrent()* rayDir;

    rayPayload.rayConeWidth += rayPayload.rayConeSpreadAngle*RayTCurrent();
            
    float LOD = RayCalcLOD(currentvertex, rayPayload.rayConeWidth, rayDir, worldNormal);

    float4 color = _Color*SampleTex2D(_MainTex, sampler_MainTex, uv, LOD);
    #ifdef USE_ALPHA
        float alpha = color.w;
    #else
        float alpha = 1;
    #endif
    color = color*_Intensity;

    float3 specColor = _SpecularColor*SampleTex2D(_SpecularMap, sampler_SpecularMap, uv, LOD).rgb;

    #ifdef USE_NORMALMAP
        float4 tangentNormal = SampleTex2D(_NormalMap, sampler_NormalMap, uv, LOD);        
                    
        RayCalcNormalMap(tangentNormal, _NormalStrength, currentvertex, worldNormal);
    #endif
			
    float3 specular = 0;
    half shadowFactor = 0;
    half3 indirect = _GlossyEnvironmentColor.xyz;
    float3 diffuse = 0;

    float specularLuminance = Luminance(specColor);

    #ifndef UNLIT
        RayMainLightCalc(worldNormal, worldPos, _SpecularFactor, _SpecularStrength*specularLuminance, rayPayload, shadowFactor, specular, diffuse);
        #ifndef  DISABLE_ADDITIONAL_LIGHTS
            RayAdditionalLightCalc(worldNormal, worldPos, _SpecularFactor, _SpecularStrength*specularLuminance, rayPayload, shadowFactor, specular, diffuse);
        #endif
    #else
        diffuse = 1;
        shadowFactor = 1;
    #endif
			
    if(_useDropShadows && rayPayload.depth < 1)
        RayDropShadowRay(worldPos, shadowFactor);				

    //toonShading lol
    //shadowFactor = smoothstep(0.47f, 0.53f, shadowFactor);

    float3 reflectionColor = color.xyz;				

    #ifdef USE_REFLECTIONS
        float3 reflectDir = reflect(rayDir, worldNormal); 
			    
        bool shouldReflect = false;

        if(RayShouldReflect(_Reflection, rayPayload))
            RayReflectionCalc(worldPos, reflectDir, _Reflection*specColor, rayPayload, reflectionColor);                             
    #endif

    if(rayPayload.depth < 1 && _maxIndirectDepth != 0)
        RayIndirectCalc(worldPos, worldNormal, 1, rayPayload, indirect);

    #ifdef USE_ALPHA
        if(alpha < 1 && rayPayload.depth < _maxRefractionDepth)
            RayTransparentCalc(alpha, worldPos, worldNormal, _Refraction, rayPayload, color, reflectionColor);
    #endif

    rayPayload.color += float4((lerp(color.xyz, reflectionColor, _Reflection)*lerp(1, (diffuse+indirect), alpha)), 1);
    rayPayload.color += float4(specular*specColor*alpha, 0);
    rayPayload.color *= float4(lerp(1, saturate(shadowFactor+indirect), alpha), 1);

    // stop if we have reached max recursion depth
    if(rayPayload.depth +1 == gMaxDepth)
    {
        return;
    }
}
