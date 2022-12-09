#pragma vertex vert
#pragma fragment frag

#pragma shader_feature_local _ USE_ALPHA
#pragma shader_feature_local _ USE_REFLECTIONS 
#pragma shader_feature_local _ USE_NORMALMAP            
#pragma shader_feature_local _ DISABLE_ADDITIONAL_LIGHTS
#pragma shader_feature_local _ UNLIT

#include "RasterHelpers.cginc"
#include "HLSLSupport.cginc"

struct appdata
{
	float4 vertex : POSITION;
	float3 normal : NORMAL;
	float3 tangent : TANGENT;
	float2 uv : TEXCOORD0;
};

struct v2f
{
	float4 vertex : SV_POSITION;
	float2 uv : TEXCOORD0;
	float3 viewdir : TEXCOORD1;

	float3 tangent : TEXCOORD3;
	float3 bitangent : TEXCOORD4;
	float3 normal : TEXCOORD5;
};

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

	float _Intensity = 1;
	float _Reflection = 0;
	                
	float _SpecularStrength = 1;
	half _SpecularFactor = 60;
CBUFFER_END


v2f vert(appdata v)
{
	v2f o;

	o.vertex = TransformObjectToHClip(v.vertex);
	o.uv = TRANSFORM_TEX(v.uv, _MainTex);
	o.viewdir = GetWorldSpaceViewDir(mul(unity_ObjectToWorld, v.vertex));	

	// calc Normal, Binormal, Tangent vector in world space
	// cast 1st arg to 'float3x3' (type of input.normal is 'float3')
	float3 worldNormal = TransformObjectToWorldDir(v.normal);
	float3 worldTangent = TransformObjectToWorldDir(v.tangent);
	
	float3 binormal = cross(v.normal, v.tangent.xyz);// *v.tangent.w;
	float3 worldBinormal = TransformObjectToWorldDir(binormal);

	// and, set them
	o.normal = normalize(worldNormal);
	o.tangent = normalize(worldTangent);
	o.bitangent = normalize(worldBinormal);

	return o;
}

float4 frag(v2f i) : SV_Target
{
	float3 normalDirection = normalize(i.normal);	

	#ifdef USE_NORMALMAP
		half4 tangentNormal = _NormalMap.Sample(sampler_NormalMap, i.uv);
	
		tangentNormal = half4(normalize(UnpackScaleNormal(tangentNormal, _NormalStrength)), 1);

		float3x3 TBN = float3x3(normalize(i.tangent), normalize(i.bitangent), normalize(i.normal));
		TBN = transpose(TBN);

		// finally we got a normal vector from the normal map
		normalDirection = mul(TBN, tangentNormal);
	#endif

	
	
	float3 specular = 0;
	half shadowFactor = 0;
	half3 indirect = _GlossyEnvironmentColor.xyz;
	float3 diffuse = 0;	

	float3 color = _Color*_MainTex.Sample(sampler_MainTex, i.uv)*_Intensity;
	float3 specColor = _SpecularColor*_SpecularMap.Sample(sampler_SpecularMap, i.uv).rgb;

	float specularLuminance = Luminance(specColor);

	MainLightCalc(normalDirection, i.viewdir, _SpecularFactor, _SpecularStrength*specularLuminance, shadowFactor, specular, diffuse);

	half3 reflectColor = color.xyz;
	#ifdef USE_REFLECTIONS
		half3 reflection = reflect(-i.viewdir, normalDirection);
		half4 skyData = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflection, 0);
		reflectColor = DecodeHDR (skyData, unity_SpecCube0_HDR)*_Reflection*specColor*_Intensity;
	#endif	
	
	float3 lightFinal = float3(lerp(color.xyz, reflectColor, _Reflection)*(diffuse+indirect));
	lightFinal += float3(specular*_SpecularColor);
	lightFinal *= float3(saturate(shadowFactor+indirect));

	return float4(lightFinal, 1);
}