#include "UnityCG.cginc"
#include "RasterHelpers.cginc"

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

float4 _Color;
Texture2D _MainTex;
float4 _MainTex_ST;
SamplerState sampler_MainTex;

float3 _SpecularColor;
Texture2D _SpecularMap;
float3 _SpecularMap_ST;
SamplerState sampler_SpecularMap;
float _SpecularStrength;
float _SpecularPower;    

Texture2D _NormalMap;
float4 _NormalMap_ST;
SamplerState sampler_NormalMap;
float _NormalStrength;

float _Reflection;

uniform float4 _LightColor0;
uniform float4 _GlossyEnvironmentColor;
uniform int _renderShadows;

v2f vert(appdata v)
{
	v2f o;

	o.vertex = UnityObjectToClipPos(v.vertex);
	//o.normal = UnityObjectToWorldDir(v.normal);
	o.uv = TRANSFORM_TEX(v.uv, _MainTex);
	o.viewdir = UnityWorldSpaceViewDir(mul(unity_ObjectToWorld, v.vertex));
	

	// calc Normal, Binormal, Tangent vector in world space
	// cast 1st arg to 'float3x3' (type of input.normal is 'float3')
	float3 worldNormal = UnityObjectToWorldDir(v.normal);
	float3 worldTangent = UnityObjectToWorldDir(v.tangent);
	
	float3 binormal = cross(v.normal, v.tangent.xyz);// *v.tangent.w;
	float3 worldBinormal = UnityObjectToWorldDir(binormal);

	// and, set them
	o.normal = normalize(worldNormal);
	o.tangent = normalize(worldTangent);
	o.bitangent = normalize(worldBinormal);

	return o;
}

fixed4 frag(v2f i) : SV_Target
{
	float3 normalDirection = normalize(i.normal);

	half4 tangentNormal = _NormalMap.Sample(sampler_NormalMap, i.uv);

	if(tangentNormal.z != 0 || _NormalStrength == 0)
    {
		tangentNormal = half4(normalize(UnpackScaleNormal(tangentNormal, _NormalStrength)), 1);

		float3x3 TBN = float3x3(normalize(i.tangent), normalize(i.bitangent), normalize(i.normal));
		TBN = transpose(TBN);

		// finally we got a normal vector from the normal map
		normalDirection = mul(TBN, tangentNormal);
	}

	half3 reflectColor = 0;
	if(_Reflection != 0)
	{
		half3 reflection = reflect(-i.viewdir, normalDirection);
		half4 skyData = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflection, 0);
    	reflectColor = DecodeHDR (skyData, unity_SpecCube0_HDR);
	}

	//float3 normalDirection = normalize(i.normal);
	float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);
	
	float facing = max(0, dot(normalDirection, lightDir));	

	float3 color = _Color*_MainTex.Sample(sampler_MainTex, i.uv);
	float3 specColor = _SpecularColor*_SpecularMap.Sample(sampler_SpecularMap, i.uv).rgb;

	color = lerp(color, reflectColor*specColor, _Reflection);

	// specular highlights
	half3 halfDir = normalize(lightDir + i.viewdir);
    half3 specAngle = max(dot(halfDir, normalDirection), 0.0);
    float3 specular = pow(specAngle, _SpecularPower)*_SpecularStrength*specColor*facing;

	float3 ambient = _GlossyEnvironmentColor.xyz+facing;

	float3 lightFinal = (_LightColor0.xyz*color + specular*_SpecularColor)*ambient;

	return float4(lightFinal, 1);
}