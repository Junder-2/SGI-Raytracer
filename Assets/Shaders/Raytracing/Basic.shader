Shader "RayTracing/DxrDiffuse"
{   
	Properties
	{
        _MainTex ("MainTex", 2D) = "white" {}
		_Color ("Color", Color) = (1, 1, 1, 1)
        _Intensity ("Intensity", Range(1, 10)) = 1
        _Reflection ("Reflection", Range(0, 1)) = 0
        _Refraction ("Refraction", Range(0, 10)) = 0
        [Toggle]_CullBackfaces ("CullBackfaces", Float) = 1
        _AlphaClip ("AlphaClip", Range(0, 1)) = 0
        //_Metallic ("Metallic", float) = 0
        _SpecularMap ("SpecularMap", 2D) = "white" {}
        _SpecularColor ("SpecularColor", Color) = (1, 1, 1, 1)
        _SpecularStrength ("SpecularStrength", Range(0, 1)) = 0.5
        _SpecularFactor ("SpecularFactor", Range(0, 100)) = 60

        _NormalMap ("NormalMap", 2D) = "black" {}
        _NormalStrength ("NormalStrength", float) = 1

        [Toggle]_UseAlpha ("UseAlpha", Float) = 0
        [Toggle]_ReceiveShadows ("ReceiveShadows", Float) = 1
        [Toggle]_ReflectionOverride ("ReflectionOverride", Float) = 0
        [Toggle]_DisableAdditionalLights ("DisableAdditionalLights", Float) = 0
        [Toggle]_CastDropShadow("CastDropShadow", Float) = 0
        _ShadowOffset ("ShadowOffset", Range(-.1, .1)) = 0
        //_FakeThickness ("FakeThickness", Range(0, 1)) = 0
	}

    CustomEditor "DXRShaderEditor"

	SubShader
	{
		Tags { "RenderType"="Opaque" }
		LOD 100

		// basic rasterization pass that will allow us to see the material in SceneView
		Pass
		{
            Tags{ "LightMode" = "UniversalForward" }

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#include "SimpleLit.cginc"
			ENDCG
		}

		// ray tracing pass
		Pass
		{
			Name "MyRaytracingPass"
			Tags{ "LightMode" = "MyRaytracingPass" }

			HLSLPROGRAM

			#pragma raytracing Raytracer

            #pragma shader_feature _UseAlpha
            #pragma shader_feature _UseReflections 
            #pragma shader_feature _UseNormalMap
					
            #include "HelperFunc.cginc"

            float _Intensity;
            float _Reflection;
            float _Refraction;
            
            float _SpecularStrength;
            half _SpecularFactor;           

            bool _DisableAdditionalLights;
            bool _CastDropShadow;            

            [shader("anyhit")]
            void anyHit (inout RayPayload rayPayload , AttributeData attributeData)
            {                
                if(_useDropShadows)
                {
                    uint rayFlags = RayFlags();

                    if((rayFlags & DROPSHADOW_FLAG) == DROPSHADOW_FLAG && !_CastDropShadow)
                        IgnoreHit();

                }

                #ifdef _UseAlpha
                // compute vertex data on ray/triangle intersection
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

                half alpha = (_Color*_MainTex.SampleLevel(sampler_MainTex, uv, LOD)).w;

                if(alpha <= _AlphaClip)
                    IgnoreHit();

                //float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
                //float3 worldNormal = normalize(mul(objectToWorld, currentvertex.rawnormalOS));            

                #endif    
            }            

			[shader("closesthit")]
			void ClosestHit(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes)
			{
                float3 debug = 0;

				// compute vertex data on ray/triangle intersection
				IntersectionVertex currentvertex;
				GetCurrentIntersectionVertex(attributeData, currentvertex);

                // transform normal to world space
                float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
				float3 worldNormal = normalize(mul(objectToWorld, currentvertex.normalOS));
                float3 rawNormal = normalize(mul(objectToWorld, currentvertex.rawnormalOS));

                float3 rayOrigin = WorldRayOrigin();
				float3 rayDir = WorldRayDirection();
                float3 worldPos = rayOrigin + RayTCurrent()* rayDir;   

                float dist = distance(rayOrigin, worldPos);
                rayPayload.dist = dist;

                rayPayload.rayConeWidth += rayPayload.rayConeSpreadAngle*dist;

                float pixelHeight = 0; float pixelWidth = 0;
                _MainTex.GetDimensions(pixelWidth, pixelHeight);
                pixelWidth *= _MainTex_ST.x;
                pixelHeight *= _MainTex_ST.y;
                
                float LOD = log2((currentvertex.texCoord0Area*pixelWidth*pixelHeight)/currentvertex.triangleArea)*.5;
                LOD += log2 (abs(rayPayload.rayConeWidth));
                LOD += 0.5 * log2 (pixelWidth * pixelHeight);
                LOD -= log2(abs(dot(rayDir , worldNormal)));

                LOD = max(log2(LOD)-LODbias, 0);

                //debug = LOD/lodLevels;

                float2 uv = TRANSFORM_TEX(currentvertex.texCoord0, _MainTex);

                float4 color = _Color*_MainTex.SampleLevel(sampler_MainTex, uv, LOD);
                #ifdef _UseAlpha
                    float alpha = color.w;
                #else
                    float alpha = 1;
                #endif
                float3 specColor = _SpecularColor*_SpecularMap.SampleLevel(sampler_SpecularMap, uv, LOD);

                #ifdef _UseNormalMap
                    float4 tangentNormal = _NormalMap.SampleLevel(sampler_NormalMap, uv, LOD);               
                    
                    CalcNormalMap(tangentNormal, _NormalStrength, currentvertex, worldNormal);
                #endif

                float3 reflectDir = reflect(rayDir, worldNormal);  

                //float3 lightColor = 0;  
                float3 specular = 0;
                half shadowFactor = 0;
                half3 indirect = _GlossyEnvironmentColor.xyz;
                float3 diffuse = 0;
               

                int shadowSamples = _renderShadows;

                MainLightCalc(worldNormal, worldPos, _SpecularFactor, _SpecularStrength*specColor, rayPayload, shadowFactor, specular, diffuse);
                //diffuse += lightColor;

                if(!_DisableAdditionalLights)
                    AdditionalLightCalc(worldNormal, worldPos, _SpecularFactor, _SpecularStrength*specColor, rayPayload, shadowFactor, specular, diffuse);

                if(_useDropShadows && !_CastDropShadow && rayPayload.depth < 1)
                    DropShadowRay(worldPos, shadowFactor);

                //toonShading lol
                //shadowFactor = smoothstep(0.47f, 0.53f, shadowFactor);

                float3 reflect = color.xyz;             

                #ifdef _UseReflections
                    bool shouldReflect = false;

                    if(ShouldReflect(_Reflection, rayPayload))
                        ReflectionCalc(worldPos, reflectDir, _Reflection*_SpecularColor, rayPayload, reflect);                             
                #endif

                if(rayPayload.depth < 1 && _maxIndirectDepth != 0)
                    IndirectCalc(worldPos, worldNormal, 1, rayPayload, indirect);

                #ifdef _UseAlpha
                    if(alpha < 1 && rayPayload.depth < _maxRefractionDepth)
                        TransparentCalc(alpha, worldPos, worldNormal, _Refraction, rayPayload, color, reflect);
                #endif
  
                rayPayload.color += float4(lerp(color.xyz, reflect, _Reflection)*lerp(1, diffuse, alpha), 1)*_Intensity;
                rayPayload.color += float4(specular*_SpecularColor*alpha, 0);
                rayPayload.color *= float4(lerp(1, shadowFactor + indirect, alpha), 1);

                //rayPayload.color = float4(debug, 1);

                // stop if we have reached max recursion depth
				if(rayPayload.depth +1 == gMaxDepth)
                {
                    return;
                }
			}    

			ENDHLSL
		}
	}
}