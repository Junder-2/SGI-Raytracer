Shader "RayTracing/DxrDiffuse"
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
		[Toggle(CAST_SHADOWS)]_CastShadows ("CastShadows", Float) = 1
        [Toggle(RECEIVE_SHADOWS)]_ReceiveShadows ("ReceiveShadows", Float) = 1
        [Toggle(REFLECTION_OVERRIDE)]_ReflectionOverride ("ReflectionOverride", Float) = 0
        [Toggle(UNLIT)]_Unlit("Unlit", Float) = 0
        [Toggle(DISABLE_ADDITIONAL_LIGHTS)]_DisableAdditionalLights ("DisableAdditionalLights", Float) = 0
		
        [HideInInspector] _Cull("Cull mode", Float) = 2 // 2 is "Back"
		[HideInInspector] _SourceBlend("Source blend", Float) = 0
        [HideInInspector] _DestBlend("Destination blend", Float) = 0
        [HideInInspector] _ZWrite("ZWrite", Float) = 0
	}

    CustomEditor "DXRShaderEditor"

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
			#include "SimpleLit.cginc"
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
			#include "SimpleDepthPass.cginc"
			ENDHLSL
		}
	}
}