Shader "RayTracing/DxrScroll"
{
	Properties
	{
        _MainTex ("MainTex", 2D) = "white" {}
		_Color ("Color", Color) = (1, 1, 1, 1)
        _Intensity ("Intensity", Range(1, 10)) = 1
        _Reflection ("Reflection", Range(0, 1)) = 0
        _Refraction ("Refraction", Range(0, 10)) = 0
        _CullBackfaces ("CullBackfaces", Range(0, 1)) = 1
        _AlphaClip ("AlphaClip", Range(0, 1)) = 0
        //_Metallic ("Metallic", float) = 0
        _SpecularMap ("SpecularMap", 2D) = "white" {}
        _SpecularColor ("SpecularColor", Color) = (1, 1, 1, 1)
        _SpecularStrength ("SpecularStrength", Range(0, 1)) = 0.5
        _SpecularPower ("SpecularPower", Range(0, 100)) = 60

        _NormalMap ("NormalMap", 2D) = "black" {}
        _NormalStrength ("NormalStrength", float) = 1

        _ReceiveShadows ("ReceiveShadows", Range(0, 1)) = 1
        _ReflectionOverride ("ReflectionOverride", Range(0, 1)) = 0
        _ShadowOffset ("ShadowOffset", Range(-.1, .1)) = 0

        _ScrollSpeed("ScrollSpeed", float) = 1
        _ScrollDir("ScrollDirection", Vector) = (0, 1, 0)
	}
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
					
            #include "HelperFunc.cginc"

            float _ScrollSpeed;
            float2 _ScrollDir;

            [shader("anyhit")]
            void anyHit (inout RayPayload rayPayload , AttributeData attributeData)
            {
                // compute vertex data on ray/triangle intersection
				IntersectionVertex currentvertex;
				GetCurrentIntersectionVertex(attributeData, currentvertex);
                
                float3 worldPos = WorldRayOrigin() + RayTCurrent()* WorldRayDirection();     
                float dist = distance(WorldRayOrigin(), worldPos);

                float pixelHeight = 0; float pixelWidth = 0;
                _MainTex.GetDimensions(pixelWidth, pixelHeight);
                pixelWidth *= _MainTex_ST.x;
                pixelHeight *= _MainTex_ST.y;
                
                float LOD = log2((currentvertex.texCoord0Area*pixelWidth*pixelHeight)/currentvertex.triangleArea)*.5;
                LOD += log2 (abs(rayPayload.rayConeWidth));
                LOD += 0.5 * log2 (pixelWidth * pixelHeight);

                LOD = max(log2(LOD)-LODbias, 0);

                float2 uv = TRANSFORM_TEX(currentvertex.texCoord0, _MainTex);

                uv.x += _ScrollSpeed*_Time/10.0f*normalize(_ScrollDir).x;
                uv.y += _ScrollSpeed*_Time/10.0f*normalize(_ScrollDir).y;

                float alpha = (_Color*_MainTex.SampleLevel(sampler_MainTex, uv, LOD)).w;

                if(alpha <= _AlphaClip)
                    IgnoreHit();

                //float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
				//float3 worldNormal = normalize(mul(objectToWorld, currentvertex.rawnormalOS));
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


                /*float normalLength = 0;

                if(length(normalize(currentvertex.normalOS) - normalize(currentvertex.rawnormalOS)) > 0.0000005)
                {
                    normalLength = max(length(normalize(currentvertex.normalOS) - normalize(currentvertex.rawnormalOS)), 0)*currentvertex.triangleArea;
                }
                
                //bool isBackFace = dot(GetWorldSpaceViewDir(worldPos), worldNormal) < 0.f;

                //if(isBackFace)
                //    worldNormal = -worldNormal;

                float3 correctedPos = worldPos + normalLength*worldNormal;*/

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

                uv.x += _ScrollSpeed*_Time/10.0f*normalize(_ScrollDir).x;
                uv.y += _ScrollSpeed*_Time/10.0f*normalize(_ScrollDir).y;

                float4 color = _Color*_MainTex.SampleLevel(sampler_MainTex, uv, LOD);
                float alpha = color.w;
                float3 specColor = _SpecularColor*_SpecularMap.SampleLevel(sampler_SpecularMap, uv, LOD);

                float4 tangentNormal = _NormalMap.SampleLevel(sampler_NormalMap, uv, LOD);               
				
                if(tangentNormal.z != 0 && _NormalStrength != 0)
                    CalcNormalMap(tangentNormal, _NormalStrength, currentvertex, worldNormal);

                float3 reflectDir = reflect(rayDir, worldNormal);  

                //float3 lightColor = 0;  
                float3 specular = 0;
                float shadowFactor = 0;
                half3 ambient = _GlossyEnvironmentColor.xyz;
                float3 diffuse = 0;
               

                int shadowSamples = _renderShadows;

                MainLightCalc(worldNormal, worldPos, _SpecularFactor, _SpecularStrength*specColor, rayPayload, shadowFactor, specular, diffuse);
                //diffuse += lightColor;

                AdditionalLightCalc(worldNormal, worldPos, _SpecularFactor, _SpecularStrength*specColor, rayPayload, shadowFactor, specular, diffuse);

                //toonShading lol
                //shadowFactor = smoothstep(0.47f, 0.53f, shadowFactor);

                
                half3 indirect = 0;
                float3 reflect = color.xyz;

                bool shouldReflect = false;
                
                if(ShouldReflect(_Reflection, rayPayload))
                    ReflectionCalc(worldPos, reflectDir, _Reflection*_SpecularColor, rayPayload, reflect);             

                if(rayPayload.depth < 1 && _maxIndirectDepth != 0)
                    IndirectCalc(worldPos, worldNormal, 1, rayPayload, indirect);

                if(alpha < 1 && rayPayload.depth < _maxRefractionDepth)
                    TransparentCalc(alpha, worldPos, worldNormal, _Refraction, rayPayload, color, reflect);
  
                rayPayload.color += float4(lerp(color.xyz, reflect, _Reflection)*lerp(1, diffuse, alpha), 1)*_Intensity;
                rayPayload.color += float4(specular*_SpecularColor*alpha, 0);
                rayPayload.color *= float4(lerp(1, shadowFactor + ambient + indirect, alpha), 1);

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