Shader "RayTracing/DxrScroll"
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
		
		_Reflection ("Reflection", Range(0, 1)) = 0
        _Refraction ("Refraction", Range(0, 10)) = 0
        
        //_Metallic ("Metallic", float) = 0
		
		[Space(20)]
		
		_ShadowOffset ("ShadowOffset", Range(-.1, .1)) = 0
		_AlphaClip ("AlphaClip", Range(0, 1)) = 0
		
		[Space(20)]
		
		[Toggle]_CullBackfaces ("CullBackfaces", Float) = 1
        [Toggle(USE_ALPHA)]_UseAlpha ("UseAlpha", Float) = 0
        [Toggle(RECEIVE_SHADOWS)]_ReceiveShadows ("ReceiveShadows", Float) = 1
        [Toggle(REFLECTION_OVERRIDE)]_ReflectionOverride ("ReflectionOverride", Float) = 0
        [Toggle(UNLIT)]_Unlit("Unlit", Float) = 0
        [Toggle(DISABLE_ADDITIONAL_LIGHTS)]_DisableAdditionalLights ("DisableAdditionalLights", Float) = 0
        [Toggle(CAST_DROP_SHADOW)]_CastDropShadow("CastDropShadow", Float) = 0        
        //_FakeThickness ("FakeThickness", Range(0, 1)) = 0

        _ScrollSpeed("ScrollSpeed", float) = 1
        _ScrollDir("ScrollDirection", Vector) = (0, 1, 0)
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

			#include "StandardRaytracing.cginc"

			ENDHLSL
		}
	}
}