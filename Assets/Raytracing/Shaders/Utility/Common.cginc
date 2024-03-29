#ifndef COMMON_CGING
#define COMMON_CGING

#include "UnityRaytracingMeshUtils.cginc"

#ifndef SHADER_STAGE_COMPUTE
// raytracing scene
RaytracingAccelerationStructure  _RaytracingAccelerationStructure;
#endif

#define RAYTRACING_DEFAULT (1 << 0)
#define RAYTRACING_SHADOW (1 << 1)
#define SHADOWRAY_FLAG 0x200

#define EPSILON         1.0e-4

// max recursion depth
static const uint gMaxDepth = 3;

static const float gShadowOffset = .05f;

static const float LODbias = 1;

uniform int gRenderShadows;
uniform int gReflectionMode;
uniform int gMaxReflectDepth;
uniform int gMaxIndirectDepth;
uniform int gMaxRefractionDepth;

uniform int gClipDistance;
uniform float gSunSpread;

// compute random seed from one input
// http://reedbeta.com/blog/quick-and-easy-gpu-random-numbers-in-d3d11/
uint initRand(uint seed)
{
	seed = (seed ^ 61) ^ (seed >> 16);
	seed *= 9;
	seed = seed ^ (seed >> 4);
	seed *= 0x27d4eb2d;
	seed = seed ^ (seed >> 15);

	return seed;
}

// compute random seed from two inputs
// https://github.com/nvpro-samples/optix_prime_baking/blob/master/random.h
uint initRand(uint seed1, uint seed2)
{
	uint seed = 0;

	[unroll]
	for(uint i = 0; i < 16; i++)
	{
		seed += 0x9e3779b9;
		seed1 += ((seed2 << 4) + 0xa341316c) ^ (seed2 + seed) ^ ((seed2 >> 5) + 0xc8013ea4);
		seed2 += ((seed1 << 4) + 0xad90777d) ^ (seed1 + seed) ^ ((seed1 >> 5) + 0x7e95761e);
	}
	
	return seed1;
}

// next random number
// http://reedbeta.com/blog/quick-and-easy-gpu-random-numbers-in-d3d11/
float nextRand(inout uint seed)
{
	seed = 1664525u * seed + 1013904223u;
	return float(seed & 0x00FFFFFF) / float(0x01000000);
}

// ray payload
struct RayPayload
{
	// Color of the ray
	float4 color;
	// Random Seed
	uint randomSeed;
	// Recursion depth
	uint depth;
	uint frameIndex;
	uint data;

	float rayConeWidth;
	float rayConeSpreadAngle;
};

struct ShadowHitInfo
{ 
	bool isHit;
};

// Triangle attributes
struct AttributeData
{
	// Barycentric value of the intersection
	float2 barycentrics;
};

// Macro that interpolate any attribute using barycentric coordinates
#define INTERPOLATE_RAYTRACING_ATTRIBUTE(A0, A1, A2, BARYCENTRIC_COORDINATES) (A0 * BARYCENTRIC_COORDINATES.x + A1 * BARYCENTRIC_COORDINATES.y + A2 * BARYCENTRIC_COORDINATES.z)

// Structure to fill for intersections
struct IntersectionVertex
{
	// Object space position of the vertex
	float3 positionOS;
	// Object space normal of the vertex
	float3 normalOS;
	// Object space normal of the vertex
	float3 tangentOS;
	// UV coordinates
	float2 texCoord0;
	float2 texCoord1;
	float2 texCoord2;
	float2 texCoord3;
	// Vertex color
	float4 color;
	// Value used for LOD sampling
	float  triangleArea;
	float  texCoord0Area;
	float  texCoord1Area;
	float  texCoord2Area;
	float  texCoord3Area;

	bool frontFace;
};

// Fetch the intersetion vertex data for the target vertex
void FetchIntersectionVertex(uint vertexIndex, out IntersectionVertex outVertex)
{
	outVertex.positionOS = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributePosition);
	outVertex.normalOS   = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributeNormal);
	outVertex.tangentOS  = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributeTangent);
	outVertex.texCoord0  = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord0);
	outVertex.texCoord1  = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord1);
	outVertex.texCoord2  = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord2);
	outVertex.texCoord3  = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord3);
	outVertex.color      = UnityRayTracingFetchVertexAttribute4(vertexIndex, kVertexAttributeColor);
}

void GetCurrentIntersectionVertex(AttributeData attributeData, out IntersectionVertex outVertex, float3 viewDir = 0)
{
	// Fetch the indices of the currentr triangle
	uint3 triangleIndices = UnityRayTracingFetchTriangleIndices(PrimitiveIndex());

	// Fetch the 3 vertices
	IntersectionVertex v0, v1, v2;
	FetchIntersectionVertex(triangleIndices.x, v0);
	FetchIntersectionVertex(triangleIndices.y, v1);
	FetchIntersectionVertex(triangleIndices.z, v2);

	// Compute the full barycentric coordinates
	float3 barycentricCoordinates = float3(1.0 - attributeData.barycentrics.x - attributeData.barycentrics.y, attributeData.barycentrics.x, attributeData.barycentrics.y);

	// Interpolate all the data
	outVertex.positionOS = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.positionOS, v1.positionOS, v2.positionOS, barycentricCoordinates);
	outVertex.normalOS   = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.normalOS, v1.normalOS, v2.normalOS, barycentricCoordinates);
	outVertex.tangentOS  = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.tangentOS, v1.tangentOS, v2.tangentOS, barycentricCoordinates);
	outVertex.texCoord0  = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord0, v1.texCoord0, v2.texCoord0, barycentricCoordinates);
	outVertex.texCoord1  = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord1, v1.texCoord1, v2.texCoord1, barycentricCoordinates);
	outVertex.texCoord2  = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord2, v1.texCoord2, v2.texCoord2, barycentricCoordinates);
	outVertex.texCoord3  = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord3, v1.texCoord3, v2.texCoord3, barycentricCoordinates);
	outVertex.color      = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.color, v1.color, v2.color, barycentricCoordinates);
	
	float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
	v0.positionOS = mul(objectToWorld, v0.positionOS);
	v1.positionOS = mul(objectToWorld, v1.positionOS);
	v2.positionOS = mul(objectToWorld, v2.positionOS);
	float3 vertexCross = cross(v1.positionOS - v0.positionOS, v2.positionOS - v0.positionOS);

	outVertex.frontFace = dot(viewDir, normalize(vertexCross)) < 0;

	// Compute the lambda value (area computed in object space)
	outVertex.triangleArea  = length(vertexCross);
	outVertex.texCoord0Area = abs((v1.texCoord0.x - v0.texCoord0.x) * (v2.texCoord0.y - v0.texCoord0.y) - (v2.texCoord0.x - v0.texCoord0.x) * (v1.texCoord0.y - v0.texCoord0.y));
	outVertex.texCoord1Area = abs((v1.texCoord1.x - v0.texCoord1.x) * (v2.texCoord1.y - v0.texCoord1.y) - (v2.texCoord1.x - v0.texCoord1.x) * (v1.texCoord1.y - v0.texCoord1.y));
	outVertex.texCoord2Area = abs((v1.texCoord2.x - v0.texCoord2.x) * (v2.texCoord2.y - v0.texCoord2.y) - (v2.texCoord2.x - v0.texCoord2.x) * (v1.texCoord2.y - v0.texCoord2.y));
	outVertex.texCoord3Area = abs((v1.texCoord3.x - v0.texCoord3.x) * (v2.texCoord3.y - v0.texCoord3.y) - (v2.texCoord3.x - v0.texCoord3.x) * (v1.texCoord3.y - v0.texCoord3.y));
}

half3 UnpackScaleNormal(half4 packednormal, half bumpScale)
{
	#if defined(UNITY_NO_DXT5nm)
		return packednormal.xyz * 2 - 1;
	#else
		half3 normal;
		normal.xy = (packednormal.wy * 2 - 1);
			normal.xy *= bumpScale;
		normal.z = sqrt(1.0 - saturate(dot(normal.xy, normal.xy)));
		return normal;
	#endif
}	

bool ShadowRay(float3 origin, half3 direction, float Tmin, float Tmax)
{
	RayDesc shadowRay;
    shadowRay.Origin = origin;
    shadowRay.Direction = direction;
    shadowRay.TMin = Tmin;
    shadowRay.TMax = Tmax;

	ShadowHitInfo shadowPayload;
    shadowPayload.isHit = true;

	uint flags = RAY_FLAG_FORCE_NON_OPAQUE | RAY_FLAG_SKIP_CLOSEST_HIT_SHADER | SHADOWRAY_FLAG;

    TraceRay(_RaytracingAccelerationStructure, flags, RAYTRACING_SHADOW, 0, 0, 1, shadowRay, shadowPayload);
    return (shadowPayload.isHit);
}

#endif // COMMON_CGING