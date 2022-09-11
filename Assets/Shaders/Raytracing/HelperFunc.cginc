#include "Lights.hlsl"
#include "Common.cginc"
#include "HLSLSupport.cginc"

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

float _FakeThickness;

bool _ReceiveShadows;
//bool _ReflectionOverride;
bool _CullBackfaces;
float _AlphaClip;
float _ShadowOffset;

#pragma shader_feature _ReflectionOverride
#pragma shader_feature _UseRefraction
//#pragma shader_feature _HasFakeThickness

bool ShouldReflect(float reflection, RayPayload rayPayload)
{
    bool shouldReflect = false;

    if(_maxReflectDepth == 0 || rayPayload.depth >= _maxReflectDepth)
        return shouldReflect;

    #ifndef _ReflectionOverride
        if(reflection > .5f)
            shouldReflect = true;

        else if(reflection > .35f)
            shouldReflect = rayPayload.depth < max(_maxReflectDepth-1, 1);

        else if(rayPayload.frameIndex % 2 == 0)
            shouldReflect = true;
    #else
        shouldReflect = true;
    #endif

    if(_halfTraceReflections && rayPayload.frameIndex % 2 == 0 && shouldReflect)
        shouldReflect = true;
    else if(_halfTraceReflections)
        shouldReflect = false;

    return shouldReflect;
}

float CalcLOD(Texture2D tex, IntersectionVertex vertex)
{
    float pixelHeight = 0; float pixelWidth = 0;
    
    tex.GetDimensions(pixelWidth, pixelHeight);
    float lambda = log2((vertex.texCoord0Area*pixelWidth*pixelHeight)/vertex.triangleArea)*.5;

    return lambda;
}

void CalcNormalMap(float4 tangentNormal, float normalStrength, IntersectionVertex currentvertex, inout float3 worldNormal)
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

void DropShadowRay(float3 worldPos, inout float shadowFactor)
{
    bool hit = ShadowRay(worldPos, half3(0, 1, 0), 3, 100, _cullShadowBackfaces, DROPSHADOW_FLAG);
	
    shadowFactor *= (hit ? 0.0 : 1.0f);
}

void MainLightCalc(float3 worldNormal, float3 worldPos, half specularFactor, float specularStrength, inout RayPayload rayPayload, inout float shadowFactor, inout float3 specular, inout float3 diffuse)
{
    Light mainLight = GetMainLight();
    half3 lightDir = mainLight.direction;   
    float facing = max(dot(lightDir, worldNormal), 0);  
    float shadowAmount = 1;

    float lightStrength = mainLight.distanceAttenuation*dot(mainLight.color, float3(0.2126, 0.7152, 0.0722));
    float currLightAmount = 0;

    if(mainLight.distanceAttenuation >= 0)
    {                                   
        if(_renderShadows != 0 && _ReceiveShadows)
        {  
            shadowAmount = 0;
            int maxSamples = _renderShadows;
            int samples = maxSamples;

            half3 perpX = cross(-lightDir, half3(0.f, 1.0f, 0.f));
            if (all(perpX == 0.0f)) {
                perpX.x = 1.0;
            }
            half3 perpY = cross(perpX, -lightDir);

            while(samples > 0)
            {
                float3 samplePos = (worldPos+lightDir*100.0f);
                float sampleDist = (100.0f);
                half3 sampleDir = -lightDir;

                if(_renderShadows != 1)
                {
                    float2 randomVector = float2(nextRand(rayPayload.randomSeed), nextRand(rayPayload.randomSeed)) * 2 - 1;
                    randomVector = normalize(randomVector) * saturate(length(randomVector));

                    samplePos += perpX*randomVector.x*_sunSpread + perpY*randomVector.y*_sunSpread;

                    sampleDist = length(samplePos - worldPos);
                    sampleDir = normalize(worldPos- samplePos);
                }                           

                bool hit = ShadowRay(samplePos, sampleDir, .1f, (sampleDist-gShadowOffset-_ShadowOffset), _cullShadowBackfaces, 0);

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

        diffuse += mainLight.color*mainLight.distanceAttenuation;//*shadowAmount;    

        if(rayPayload.depth < _maxReflectDepth+1 && facing != 0)
        {
            BlinnPhongCalc(lightDir, worldNormal, worldPos, specularFactor, specularStrength*currLightAmount, specular);
        }
    }
}

void AdditionalLightCalc(half3 worldNormal, float3 worldPos, half specularFactor, half specularStrength, inout RayPayload rayPayload, inout float shadowFactor, inout float3 specular, inout float3 diffuse)
{
    int pixelLightCount = GetAdditionalLightsCount();
    for (int i = 0; i < pixelLightCount; ++i) 
    {                        
        Light light = GetAdditionalLight(i, worldPos);
        float3 lightDir = light.direction;
        float facing = max((dot(lightDir, worldNormal)), 0);  

        float lightStrength = light.distanceAttenuation*dot(light.color, float3(0.2126, 0.7152, 0.0722));
        float shadowAmount = 1;

        float currLightAmount = 0;

        if(light.distanceAttenuation >= 0)
        {
            if(_renderShadows != 0 && _ReceiveShadows)
            {                
                shadowAmount = 0;
                int maxSamples = _renderShadows;
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

                    if(_renderShadows != 1)
                    {
                        half2 randomVector = half2(nextRand(rayPayload.randomSeed), nextRand(rayPayload.randomSeed)) * 2 - 1;
                        randomVector = normalize(randomVector) * saturate(length(randomVector));

                        samplePos += perpX*randomVector.x + perpY*randomVector.y;
                        sampleDist = length(samplePos - worldPos);
                        sampleDir = normalize(worldPos- samplePos);
                    }

                    bool hit = ShadowRay(samplePos, sampleDir, .1f, (sampleDist-gShadowOffset-_ShadowOffset), _cullShadowBackfaces, 0);

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

            diffuse += light.color*light.distanceAttenuation;//*shadowAmount;

            if(rayPayload.depth < _maxReflectDepth+1 && facing != 0)
            {
                BlinnPhongCalc(lightDir, worldNormal, worldPos, specularFactor, specularStrength*currLightAmount, specular);
            }
        }
    }
}

void ReflectionCalc(float3 worldPos, half3 reflectDir, float3 reflectStrength, RayPayload rayPayload, inout float3 reflect)
{
    RayDesc reflectRay;
    reflectRay.Origin = worldPos;
    reflectRay.Direction = normalize(reflectDir);
    reflectRay.TMin = 0.001;
    reflectRay.TMax = 100;

    RayPayload reflectPayload;
    reflectPayload.color = 0;
    reflectPayload.randomSeed = rayPayload.randomSeed;
    reflectPayload.depth = rayPayload.depth + 1;
    reflectPayload.dist = rayPayload.dist;
    //reflectPayload.lastPos = worldPos;
    reflectPayload.data = 0;

    TraceRay(_RaytracingAccelerationStructure, RAY_FLAG_FORCE_NON_OPAQUE, RAYTRACING_OPAQUE_FLAG, 0, 1, 0, reflectRay, reflectPayload);

    reflect = reflectPayload.color*reflectStrength;
}

void IndirectCalc(float3 worldPos, half3 worldNormal, half3 ambient, inout RayPayload rayPayload, inout half3 indirect)
{
    indirect = 0;
    int maxSamples = _maxIndirectDepth;
    int samples = maxSamples;

    while(samples > 0)
    {
        half3 randomVector = half3(nextRand(rayPayload.randomSeed), nextRand(rayPayload.randomSeed), nextRand(rayPayload.randomSeed)) * 2 - 1;
        //rayPayload.randomSeed += 1;

        float3 scatterRayDir = normalize(worldNormal+randomVector);

        RayDesc rayDesc;
        rayDesc.Origin = worldPos;
        rayDesc.Direction = scatterRayDir;
        rayDesc.TMin = 0.001;
        rayDesc.TMax = 3;

        // Create and init the scattered payload
        RayPayload scatterRayPayload;
        scatterRayPayload.color = 0;
        scatterRayPayload.randomSeed = rayPayload.randomSeed;
        scatterRayPayload.depth = rayPayload.depth + 1;			
        scatterRayPayload.dist = rayPayload.dist;
        //scatterRayPayload.lastPos = worldPos;
        scatterRayPayload.data = 0x2;

        // shoot scattered ray
        TraceRay(_RaytracingAccelerationStructure, RAY_FLAG_FORCE_NON_OPAQUE, RAYTRACING_OPAQUE_FLAG, 0, 1, 0, rayDesc, scatterRayPayload);
        
        //dist = scatterRayPayload.dist - rayPayload.dist;

        indirect += (scatterRayPayload.color*ambient)/maxSamples;

        samples--;			
    }
}

void TransparentCalc(float alpha, float3 worldPos, half3 worldNormal, float refraction, RayPayload rayPayload, inout float4 color, inout float3 reflect)
{
    float3 rayDir = WorldRayDirection();
    RayDesc transparentRay;

    int flags = RAY_FLAG_FORCE_NON_OPAQUE;

    #ifdef _UseRefraction

        //float fakeThickness = _FakeThickness/10.0f;
        /*#ifdef _HasFakeThickness
            bool frontFace = dot(rayDir, worldNormal) <= 0.0;

            if(frontFace)
            {
                float3 dir = refract(rayDir, worldNormal, 1 / (refraction/4.0+1));

                float3 newPos = worldPos + dir*fakeThickness;

                transparentRay.Origin = newPos;
                transparentRay.Direction = refract(dir, worldNormal, (refraction/4.0+1));
            }
            else
            {
                float3 newPos = worldPos - worldNormal*fakeThickness;

                float3 dir = refract(normalize(rayDir), worldNormal, 1 /(refraction/4.0+1));

                newPos = newPos + dir*fakeThickness;

                transparentRay.Origin = newPos;
                transparentRay.Direction = refract(dir, worldNormal, (refraction/4.0+1));
            }
        #else */
            float currentIoR = dot(rayDir, worldNormal) <= 0.0 ? 1 / (refraction/4.0+1) : refraction/4.0+1;

            float3 n = dot(worldNormal, rayDir) <= 0.0 ? worldNormal : -worldNormal;

            transparentRay.Origin = worldPos;
            transparentRay.Direction = refract(normalize(rayDir), n, currentIoR);
        //#endif
    #else    
        /*#ifdef _HasFakeThickness
            bool frontFace = dot(rayDir, worldNormal) <= 0.0;
            if(!frontFace)
            {
                float3 newPos = worldPos - worldNormal*fakeThickness;

                newPos = newPos + rayDir*fakeThickness;

                transparentRay.Origin = newPos;
            }
            else
            {
                float3 newPos = worldPos + rayDir*fakeThickness;

                transparentRay.Origin = newPos;
            }
        #else*/
            transparentRay.Origin = worldPos;
        //#endif
        
        transparentRay.Direction = normalize(rayDir);
    #endif
        

    if(_CullBackfaces)
        flags |= RAY_FLAG_CULL_BACK_FACING_TRIANGLES;
    
    transparentRay.TMin = 0.001;
    transparentRay.TMax = 100;

    RayPayload transPayload;
    transPayload.color = 0;
    transPayload.randomSeed = rayPayload.randomSeed;
    transPayload.depth = rayPayload.depth + 1;
    transPayload.dist = rayPayload.dist;
    //transPayload.lastPos = worldPos;
    transPayload.data = 0;

    TraceRay(_RaytracingAccelerationStructure, flags, 0xFF, 0, 1, 0, transparentRay, transPayload);

    color = float4(lerp(transPayload.color.xyz, color.xyz, alpha), 1);
    reflect = float3(lerp(transPayload.color.xyz, reflect, alpha));
}

/*float normalLength = 0;

if(length(normalize(currentvertex.normalOS) - normalize(currentvertex.rawnormalOS)) > 0.0000005)
{
    normalLength = max(length(normalize(currentvertex.normalOS) - normalize(currentvertex.rawnormalOS)), 0)*currentvertex.triangleArea;
}

//bool isBackFace = dot(GetWorldSpaceViewDir(worldPos), worldNormal) < 0.f;

//if(isBackFace)
//    worldNormal = -worldNormal;

float3 correctedPos = worldPos + normalLength*worldNormal;*/