#define _ADDITIONAL_LIGHTS
#define _ADDITIONAL_LIGHTS_VERTEX

#include "Utility/Lights.hlsl"
#include "Utility/RaytraceCommon.cginc"

CBUFFER_START(UnityPerMaterial)
    float4 _Color;
    Texture2D _MainTex;
    float4 _MainTex_ST;
    SamplerState sampler_MainTex;
    Texture2D _SpecularMap;
    float4 _SpecularMap_ST;
    SamplerState sampler_SpecularMap;
    float4 _SpecularColor;
    Texture2D _NormalMap;
    float4 _NormalMap_ST;
    SamplerState sampler_NormalMap;
    float _NormalStrength;
    Texture2D _AttributeMap;
    float4 _AttributeMap_ST;
    SamplerState sampler_AttributeMap;

    bool _DoubleSided = false;
    bool _Unlit = false;
    float _AlphaClip = 0;
    float _ShadowOffset = 0;

    float _Intensity = 1;
    float _Reflection = 0;
    float _Refraction = 0;
                
    float _SpecularStrength = 1;
    half _SpecularFactor = 60;
CBUFFER_END

#pragma shader_feature_local _ RECEIVE_SHADOWS
#pragma shader_feature_local _ CAST_SHADOWS
#pragma shader_feature_local _ REFLECTION_OVERRIDE
#pragma shader_feature_local _ USE_REFRACTION
#pragma shader_feature_local _ DOUBLESIDED

#ifndef CALCULATEUV
#define CALCULATEUV TRANSFORM_TEX(currentvertex.texCoord0, _MainTex);
#endif

bool RayShouldReflect(float reflection, RayPayload rayPayload)
{
    bool shouldReflect = false;

    if(gMaxReflectDepth == 0 || rayPayload.depth >= gMaxReflectDepth)
        return shouldReflect;

    if(gReflectionMode == 3)
        return true;    

    #ifndef REFLECTION_OVERRIDE
        if(reflection > .5f)
            shouldReflect = true;
        else if(reflection > .35f)
            shouldReflect = rayPayload.depth < max(gMaxReflectDepth-1, 1);

        if(gReflectionMode == 2)
            return shouldReflect;
    
        if(reflection < .35f && rayPayload.frameIndex % 2 == 0)
            shouldReflect = false;
    #else
        shouldReflect = true;
    #endif

    if(gReflectionMode == 0 && rayPayload.frameIndex % 2 == 0 && shouldReflect)
        shouldReflect = false;
    else if(gReflectionMode)
        shouldReflect = true;

    return shouldReflect;
}

float Luminance(float3 color)
{    
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

float RayCalcLOD(IntersectionVertex vertex, float coneWidth, float3 rayDir, float3 normal)
{
    float texCoordArea = vertex.texCoord0Area;
    float triangleArea = vertex.triangleArea;
    
    float lambda = log2(texCoordArea/triangleArea)*.5;    
    lambda += log2(abs(coneWidth));
    lambda -= log2(abs(dot(rayDir, normal)));

    return lambda-1.5;
}

float4 SampleTex2D(Texture2D tex, SamplerState sampler, float2 uv, float lod)
{
    float pixelHeight = 0, pixelWidth = 0;
    tex.GetDimensions(pixelWidth, pixelHeight);
    pixelWidth *= _MainTex_ST.x;
    pixelHeight *= _MainTex_ST.y;
    lod += log2(pixelWidth*pixelHeight)*.5;
    
    return tex.SampleLevel(sampler, uv, lod);
}

void RayCalcNormalMap(float4 tangentNormal, float normalStrength, IntersectionVertex currentvertex, inout float3 worldNormal)
{    
    tangentNormal = float4(normalize(UnpackScaleNormal(tangentNormal, normalStrength)), 1);

    float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();

    float3 worldBinormal = normalize(mul(objectToWorld, cross(currentvertex.normalOS, currentvertex.tangentOS)));
    float3 worldTangent = normalize(mul(objectToWorld, currentvertex.tangentOS));                    

    float3x3 TBN = float3x3(normalize(worldTangent), normalize(worldBinormal), normalize(worldNormal));
    TBN = transpose(TBN);

    worldNormal = mul(TBN, tangentNormal);
}

void BlinnPhongCalc(half3 lightDir, half3 worldNormal, float3 worldPos, half specularFactor, float specularStrength, inout float3 specular)
{
    float3 halfDir = normalize(lightDir + GetWorldSpaceViewDir(worldPos));
    half specAngle = max(dot(halfDir, worldNormal), 0.0);
    specular += pow(specAngle, specularFactor)*specularStrength;
}

void RayMainLightCalc(float3 worldNormal, float3 worldPos, half specularFactor, float specularStrength, inout RayPayload rayPayload, inout float shadowFactor, inout float3 specular, inout float3 diffuse)
{
    Light mainLight = GetMainLight();
    half3 lightDir = mainLight.direction;   
    float facing = max(dot(lightDir, worldNormal), 0);  
    float shadowAmount = 1;

    float lightStrength = mainLight.distanceAttenuation*Luminance(mainLight.color);

    if(mainLight.distanceAttenuation >= 0)
    {
        float currLightAmount = facing;
        #ifdef RECEIVE_SHADOWS
            if(gRenderShadows != 0)
            {
                shadowAmount = 0;
                int maxSamples = gRenderShadows;
                int samples = maxSamples;

                half3 perpX = cross(-lightDir, half3(0.f, 1.0f, 0.f));
                if (all(perpX == 0.0f)) {
                    perpX.x = 1.0;
                }
                half3 perpY = cross(perpX, -lightDir);

                while(samples > 0)
                {
                    float sampleDist = (gClipDistance*.1);
                    
                    float3 samplePos = (worldPos+lightDir*sampleDist);
                    
                    half3 sampleDir = -lightDir;

                    if(gRenderShadows != 1)
                    {
                        float2 randomVector = float2(nextRand(rayPayload.randomSeed), nextRand(rayPayload.randomSeed)) * 2 - 1;
                        randomVector = normalize(randomVector) * saturate(length(randomVector));

                        samplePos += perpX*randomVector.x*gSunSpread + perpY*randomVector.y*gSunSpread;

                        sampleDist = length(samplePos - worldPos);
                        sampleDir = normalize(worldPos- samplePos);
                    }                           

                    bool hit = ShadowRay(samplePos, sampleDir, .1f, (sampleDist-gShadowOffset-_ShadowOffset));

                    shadowAmount += (hit ? 0.0 : 1.0f)/maxSamples;
                    
                    samples--;
                }

                currLightAmount = shadowAmount*facing*lightStrength;
                shadowFactor += currLightAmount;
            }
            else
            {
                currLightAmount = facing*lightStrength;
                shadowFactor += currLightAmount;
            }
        #else
            currLightAmount = facing*lightStrength;
            shadowFactor += currLightAmount;
        #endif


        diffuse += mainLight.color*mainLight.distanceAttenuation;  

        if(rayPayload.depth < gMaxReflectDepth+1 && currLightAmount != 0)
        {
            BlinnPhongCalc(lightDir, worldNormal, worldPos, specularFactor, specularStrength*currLightAmount, specular);
        }
    }
}

void RayAdditionalLightCalc(half3 worldNormal, float3 worldPos, half specularFactor, half specularStrength, inout RayPayload rayPayload, inout float shadowFactor, inout float3 specular, inout float3 diffuse)
{
    int pixelLightCount = GetAdditionalLightsCount();
    for (uint i = 0; i < pixelLightCount; i++) 
    {
        
        Light light = GetAdditionalLight(i, worldPos);
        float3 lightDir = light.direction;
        float facing = max((dot(lightDir, worldNormal)), 0);

        float lightStrength = light.distanceAttenuation*Luminance(light.color);
        float shadowAmount = 1;

        float currLightAmount = facing;
        
        if(light.distanceAttenuation > 0)
        {
            #ifdef RECEIVE_SHADOWS
                if(gRenderShadows != 0)
                {                
                    shadowAmount = 0;
                    int maxSamples = gRenderShadows;
                    int samples = maxSamples;

                    half3 perpX = cross(-lightDir, half3(0.f, 1.0f, 0.f));
                    if (all(perpX == 0.0f)) {
                        perpX.x = 1.0;
                    }
                    half3 perpY = cross(perpX, -lightDir);

                    while(samples > 0)
                    {
                        float3 samplePos = worldPos+lightDir*light.distance;
                        float sampleDist = light.distance-gShadowOffset;
                        half3 sampleDir = -lightDir;

                        if(gRenderShadows != 1)
                        {
                            half2 randomVector = half2(nextRand(rayPayload.randomSeed), nextRand(rayPayload.randomSeed)) * 2 - 1;
                            randomVector = normalize(randomVector) * saturate(length(randomVector));

                            samplePos += perpX*randomVector.x + perpY*randomVector.y;
                            sampleDist = length(samplePos - worldPos);
                            sampleDir = normalize(worldPos- samplePos);
                        }

                        bool hit = ShadowRay(samplePos, sampleDir, .1f, (sampleDist-gShadowOffset-_ShadowOffset));

                        shadowAmount += (hit ? 0.0 : 1.0f)/maxSamples;
                        
                        samples--;
                    }
                    
                    currLightAmount = shadowAmount*facing*lightStrength;
                    shadowFactor += currLightAmount;
                }
                else
                {
                    currLightAmount = facing*lightStrength;
                    shadowFactor += currLightAmount;
                }
            #else
                currLightAmount = facing*lightStrength;
                shadowFactor += currLightAmount;
            #endif

            diffuse += light.color*currLightAmount;

            if(rayPayload.depth < gMaxReflectDepth+1 && currLightAmount != 0)
            {
                BlinnPhongCalc(lightDir, worldNormal, worldPos, specularFactor, specularStrength*currLightAmount, specular);
            }
        }
    }
}

void RayReflectionCalc(float3 worldPos, half3 reflectDir, float3 reflectStrength, RayPayload rayPayload, inout float3 reflection)
{
    RayDesc reflectRay;
    reflectRay.Origin = worldPos;
    reflectRay.Direction = normalize(reflectDir);
    reflectRay.TMin = 0.001;
    reflectRay.TMax = gClipDistance*.1;

    RayPayload reflectPayload;
    reflectPayload.color = 0;
    reflectPayload.randomSeed = rayPayload.randomSeed;
    reflectPayload.depth = rayPayload.depth + 1;
    reflectPayload.data = 0;

    TraceRay(_RaytracingAccelerationStructure, 0, RAYTRACING_DEFAULT, 0, 1, 0, reflectRay, reflectPayload);

    reflection = reflectPayload.color*reflectStrength*_Intensity;
}

void RayIndirectCalc(float3 worldPos, half3 worldNormal, half3 ambient, inout RayPayload rayPayload, inout half3 indirect)
{
    indirect = 0;
    int maxSamples = gMaxIndirectDepth;
    int samples = maxSamples;

    while(samples > 0)
    {
        half3 randomVector = half3(nextRand(rayPayload.randomSeed), nextRand(rayPayload.randomSeed), nextRand(rayPayload.randomSeed)) * 2 - 1;

        float3 scatterRayDir = normalize(worldNormal+randomVector);

        RayDesc rayDesc;
        rayDesc.Origin = worldPos;
        rayDesc.Direction = scatterRayDir;
        rayDesc.TMin = 0.001;
        rayDesc.TMax = 3;
        
        RayPayload scatterRayPayload;
        scatterRayPayload.color = 0;
        scatterRayPayload.randomSeed = rayPayload.randomSeed;
        scatterRayPayload.depth = rayPayload.depth + 1;			
        scatterRayPayload.data = 0x2;
        
        TraceRay(_RaytracingAccelerationStructure, 0, RAYTRACING_DEFAULT, 0, 1, 0, rayDesc, scatterRayPayload);
        
        indirect += (scatterRayPayload.color*ambient)/maxSamples;

        samples--;			
    }
}

void RayTransparentCalc(float alpha, float3 worldPos, half3 worldNormal, float refraction, RayPayload rayPayload, inout float4 color, inout float3 reflect)
{
    float3 rayDir = WorldRayDirection();
    RayDesc transparentRay;

    int flags = RAY_FLAG_CULL_BACK_FACING_TRIANGLES;

    #ifdef USE_REFRACTION
        float currentIoR = dot(rayDir, worldNormal) <= 0.0 ? 1 / (refraction*.25+1) : refraction*.25+1;

        float3 n = dot(worldNormal, rayDir) <= 0.0 ? worldNormal : -worldNormal;

        transparentRay.Origin = worldPos;
        transparentRay.Direction = refract(normalize(rayDir), n, currentIoR);
    #else    
        transparentRay.Origin = worldPos;        
        transparentRay.Direction = normalize(rayDir);
    #endif
    
    transparentRay.TMin = 0.001;
    transparentRay.TMax = gClipDistance*.75;

    RayPayload transPayload;
    transPayload.color = 0;
    transPayload.randomSeed = rayPayload.randomSeed;
    transPayload.depth = rayPayload.depth + 1;
    transPayload.data = 0;

    TraceRay(_RaytracingAccelerationStructure, flags, RAYTRACING_DEFAULT, 0, 1, 0, transparentRay, transPayload);

    color = float4(lerp(transPayload.color.xyz, color.xyz, alpha), 1);
    reflect = float3(lerp(transPayload.color.xyz, reflect, alpha));
}