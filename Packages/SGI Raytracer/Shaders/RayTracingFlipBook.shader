Shader "RayTracing/DxrFlipBook"
{
	Properties
	{
        [MainTexture]_MainTex ("MainTex", 2D) = "white" {}
		[MainColor]_Color ("Color", Color) = (1, 1, 1, 1)
        _Intensity ("Intensity", Range(1, 10)) = 1
		
		[Space(40)]
		
		_SpecularMap ("SpecularMap", 2D) = "white" {}
        _SpecularColor ("SpecularColor", Color) = (1, 1, 1, 1)
        _SpecularStrength ("SpecularStrength", Range(0, 1)) = 0.5
        _SpecularFactor ("SpecularFactor", Range(0.001, 100)) = 60
		
		[Space(40)]

        [Normal]_NormalMap ("NormalMap", 2D) = "black" {}
        _NormalStrength ("NormalStrength", float) = 1
		
		[Space(20)]
		
		_AttributeMap ("AttributeMap", 2D) = "white" {}
		_Reflection ("Reflection", Range(0, 1)) = 0
        _Refraction ("Refraction", Range(0, 10)) = 0
		
		[Space(20)]
		
		_ShadowOffset ("ShadowOffset", Range(-.1, .1)) = 0
		_AlphaClip ("AlphaClip", Range(0, 1)) = 0
		
		[Space(20)]
		
		[Toggle(DOUBLESIDED)]_DoubleSided ("Double Sided", Float) = 1
        [Toggle(USE_ALPHA)]_UseAlpha ("UseAlpha", Float) = 0
        [Toggle(RECEIVE_SHADOWS)]_ReceiveShadows ("ReceiveShadows", Float) = 1
		[Toggle(CAST_SHADOWS)]_CastShadows ("CastShadows", Float) = 1
        [Toggle(REFLECTION_OVERRIDE)]_ReflectionOverride ("ReflectionOverride", Float) = 0
        [Toggle(UNLIT)]_Unlit("Unlit", Float) = 0
        [Toggle(DISABLE_ADDITIONAL_LIGHTS)]_DisableAdditionalLights ("DisableAdditionalLights", Float) = 0

        _FlipSpeed("Speed", Float) = 1
		_Width("Width", float) = 1
		_Height("Height", float) = 1
		
        [HideInInspector] _Cull("Cull mode", Float) = 2 // 2 is "Back"
		[HideInInspector] _SourceBlend("Source blend", Float) = 0
        [HideInInspector] _DestBlend("Destination blend", Float) = 0
        [HideInInspector] _ZWrite("ZWrite", Float) = 0
	}

    CustomEditor "SGI_Raytracer.Editor.DXRShaderEditor"

	SubShader
	{
		Tags {"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}

		// ray tracing pass
		Pass
		{
			Name "MyRaytracingPass"
			Tags{"LightMode" = "MyRaytracingPass"}

			HLSLPROGRAM

			#pragma raytracing Raytracer

			float _FlipSpeed;
			float _Width;
			float _Height;

			//very cursed but works
			#define CALCULATEUV \
				(TRANSFORM_TEX(currentvertex.texCoord0, _MainTex) + float2(\
			abs(floor(fmod(_FlipSpeed*_Time.y, _Width*_Height) - (_Width * floor(fmod(_FlipSpeed*_Time.y, _Width*_Height) * 1/_Width)))), \
			abs(floor(fmod(_FlipSpeed*_Time.y, _Width*_Height) * 1/_Width)))) \
			*float2(1.0, 1.0) / float2(_Width, _Height);
			
			#include "StandardRaytracing.cginc"
			
			ENDHLSL
		}
		
		// basic rasterization pass that will allow us to see the material in SceneView
		Pass
		{
			Tags{"LightMode" = "UniversalForward"}
			
			Blend[_SourceBlend][_DestBlend]
            ZWrite[_ZWrite]
			Cull[_Cull]
			
			HLSLPROGRAM
			#pragma multi_compile _ RAYTRACING_ON
			
			#if RAYTRACING_ON
				#include "EmptyShader.cginc"
			#else
				float _FlipSpeed;
				float _Width;
				float _Height;

				#define CALCULATEUV \
					(TRANSFORM_TEX(v.uv, _MainTex) + float2(\
				abs(floor(fmod(_FlipSpeed*_Time.y, _Width*_Height) - (_Width * floor(fmod(_FlipSpeed*_Time.y, _Width*_Height) * 1/_Width)))), \
				abs(floor(fmod(_FlipSpeed*_Time.y, _Width*_Height) * 1/_Width)))) \
				*float2(1.0, 1.0) / float2(_Width, _Height);
				
				#include "SimpleLit.cginc"
	            #endif			
			ENDHLSL
		}
		
		Pass
		{
			Name "DepthOnly"
			Tags{"LightMode" = "DepthOnly"}
			
            Blend[_SourceBlend][_DestBlend]
            ZWrite[_ZWrite]
			Cull[_Cull]
			ColorMask 0
			
			HLSLPROGRAM

			float _FlipSpeed;
			float _Width;
			float _Height;

			#define CALCULATEUV \
				(TRANSFORM_TEX(v.uv, _MainTex) + float2(\
			abs(floor(fmod(_FlipSpeed*_Time.y, _Width*_Height) - (_Width * floor(fmod(_FlipSpeed*_Time.y, _Width*_Height) * 1/_Width)))), \
			abs(floor(fmod(_FlipSpeed*_Time.y, _Width*_Height) * 1/_Width)))) \
			*float2(1.0, 1.0) / float2(_Width, _Height);
			
			#include "SimpleDepthPass.cginc"
			ENDHLSL
		}
		
		 Pass
        {
            Name "Selection"
            Tags { "LightMode" = "SceneSelectionPass" }

            Cull Off

            HLSLPROGRAM

			float _FlipSpeed;
			float _Width;
			float _Height;

			#define CALCULATEUV \
				(TRANSFORM_TEX(v.uv, _MainTex) + float2(\
			abs(floor(fmod(_FlipSpeed*_Time.y, _Width*_Height) - (_Width * floor(fmod(_FlipSpeed*_Time.y, _Width*_Height) * 1/_Width)))), \
			abs(floor(fmod(_FlipSpeed*_Time.y, _Width*_Height) * 1/_Width)))) \
			*float2(1.0, 1.0) / float2(_Width, _Height);
			
			#include "SimpleSelectionPass.cginc"
			ENDHLSL
        }
	}
}