#pragma vertex vert
#pragma fragment frag

#pragma shader_feature_local _ USE_ALPHACLIP
#pragma editor_sync_compilation

#include "Utility/RasterHelpers.cginc"
#include "HLSLSupport.cginc"

struct appdata
{
	float4 vertex : POSITION;
	float2 uv : TEXCOORD0;
};

struct v2f
{
	float4 vertex : SV_POSITION;
	float2 uv : TEXCOORD0;
};

CBUFFER_START(UnityPerMaterial)
	Texture2D _MainTex;
	float4 _MainTex_ST;
	SamplerState sampler_MainTex;

	float _AlphaClip = 0;
CBUFFER_END


v2f vert(appdata v)
{
	UNITY_SETUP_INSTANCE_ID(v);
	v2f o;
	o.vertex = TransformObjectToHClip(v.vertex);
	o.uv = CALCULATEUV;
	return o;
}

int _ObjectId;
int _PassValue;

float4 frag(v2f i) : SV_Target
{
	float alpha = _MainTex.Sample(sampler_MainTex, i.uv).a;
	#ifdef USE_ALPHACLIP
		clip(alpha - _AlphaClip);
	#endif

	return float4(_ObjectId, 1, _PassValue, alpha);
}