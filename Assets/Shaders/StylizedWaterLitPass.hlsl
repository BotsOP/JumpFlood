#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "WaterLighting.hlsl"

TEXTURE2D(_FoamMap); SAMPLER(sampler_FoamMap); 
TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap); 

CBUFFER_START(UnityPerMaterial)
float4 _BaseMap_ST;
float4 _BumpMap_ST;
float4 _FoamLineCorners;
half4 _BaseColor;
half4 _WaterBottomColor;
half4 _WaterTopColor;
half4 _SpecColor;
half4 _EmissionColor;
half _Smoothness;
half _Metallic;
half _BumpScale;
half3 _WaterFogColor;
half _WaterFogDensity;
half _RefractionStrength;
CBUFFER_END

struct Attributes {
	float3 positionOS : POSITION;
	float4 tangentOS    : TANGENT;
	float3 normalOS : NORMAL; 
	float2 uv : TEXCOORD0;
};

struct Interpolators {
	float4 positionCS : SV_POSITION;
	float2 uv : TEXCOORD0;
	float3 positionWS : TEXCOORD1;
	float3 normalWS : TEXCOORD2;
	half4 tangentWS : TEXCOORD3;
	half4 fogFactorAndVertexLight : TEXCOORD4;
	half2 grabPassUV : TEXCOORD6;

#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
	float4 shadowCoord              : TEXCOORD5;
#endif
};

half3 SampleNormal(float2 uv, TEXTURE2D_PARAM(bumpMap, sampler_bumpMap), half scale = half(1.0))
{
	half4 n = SAMPLE_TEXTURE2D(bumpMap, sampler_bumpMap, uv);
	return UnpackNormalScale(n, scale);
	return UnpackNormal(n);
}

void InitializeInputData(Interpolators input, half3 normalTS, out InputData inputData)
{
    inputData = (InputData)0;

#if defined(REQUIRES_WORLD_SPACE_POS_INTERPOLATOR)
    inputData.positionWS = input.positionWS;
#endif

    half3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
    float sgn = input.tangentWS.w;      // should be either +1 or -1
    float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
    half3x3 tangentToWorld = half3x3(input.tangentWS.xyz, bitangent.xyz, input.normalWS.xyz);
    inputData.tangentToWorld = tangentToWorld;
    inputData.normalWS = TransformTangentToWorld(normalTS, tangentToWorld);
    //inputData.normalWS = input.normalWS;

    inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
    inputData.viewDirectionWS = viewDirWS;

#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
    inputData.shadowCoord = input.shadowCoord;
#elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
    inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
#else
    inputData.shadowCoord = float4(0, 0, 0, 0);
#endif
	
#ifdef _ADDITIONAL_LIGHTS_VERTEX
    inputData.fogCoord = InitializeInputDataFog(float4(input.positionWS, 1.0), input.fogFactorAndVertexLight.x);
    inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;
#endif

    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
    inputData.shadowMask = SAMPLE_SHADOWMASK(input.staticLightmapUV);

#if defined(DEBUG_DISPLAY)
    inputData.vertexSH = input.vertexSH;
#endif
}

struct SurfaceOutputWater
{
	half3 albedo;
	half alpha;
	half3 normal;
};

Interpolators Vertex(Attributes input) {
	Interpolators output;

	VertexPositionInputs posnInputs = GetVertexPositionInputs(input.positionOS);
	VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS);

	half3 vertexLight = VertexLighting(posnInputs.positionWS, normInputs.normalWS);
	half fogFactor = ComputeFogFactor(posnInputs.positionCS.z);

	real sign = input.tangentOS.w * GetOddNegativeScale();
	half4 tangentWS = half4(normInputs.tangentWS.xyz, sign);
	output.tangentWS = tangentWS;

	output.positionCS = posnInputs.positionCS;
	output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
	output.normalWS = normInputs.normalWS;
	output.positionWS = posnInputs.positionWS;
	output.fogFactorAndVertexLight = half4(fogFactor, vertexLight);

	return output;
}

sampler2D _GrabbedTexture;
TEXTURE2D(_CameraDepthTexture); SAMPLER(sampler_CameraDepthTexture); 
float4 _CameraDepthTexture_TexelSize;

float Remap (float value, float from1, float to1, float from2, float to2) {
	return (value - from1) / (to1 - from1) * (to2 - from2) + from2;
}

float4 Fragment(Interpolators input) : SV_TARGET{
	float2 uv = input.uv;
	float2 fragmentPos = input.positionWS.xz;
	float2 foamUV;
	//XY is bottom left corner and ZW is top right
	foamUV.x = Remap(fragmentPos.x, _FoamLineCorners.x, _FoamLineCorners.z, 0, 1);
	foamUV.y = Remap(fragmentPos.y, _FoamLineCorners.y, _FoamLineCorners.w, 0, 1);
	float foam = saturate(SAMPLE_TEXTURE2D(_FoamMap, sampler_FoamMap, foamUV).r);
	//return float4(foam, foam, foam, 1);

	//UV mapped to screenspace
	half3 samplingPos = input.positionWS;
	half4 samplingScreenPos = mul(UNITY_MATRIX_VP, half4(samplingPos, 1.0));
	//grabPassUV.y = 1.0 - grabPassUV.y;
	
	half3 normalTS = SampleNormal((uv * _BumpMap_ST.xy) + _Time.x / 8, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap), _BumpScale);
	float2 uvOffset = normalTS.xy * _RefractionStrength;
	uvOffset.y *= _CameraDepthTexture_TexelSize.z * abs(_CameraDepthTexture_TexelSize.y);
	half2 grabPassUV = ((samplingScreenPos.xy + uvOffset) / samplingScreenPos.w) * 0.5 + 0.5;
	grabPassUV.y = 1.0 - grabPassUV.y;

	//Get water depth
	float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, grabPassUV);
	depth = LinearEyeDepth(depth, _ZBufferParams);
	float surfaceDepth = UNITY_Z_0_FAR_FROM_CLIPSPACE(samplingScreenPos.z);
	float depthDifference = depth - surfaceDepth;
	depthDifference = min(20, depthDifference);

	//if below water apply distortion
	if(depthDifference < 0){
		grabPassUV = (samplingScreenPos.xy / samplingScreenPos.w) * 0.5 + 0.5;
		grabPassUV.y = 1.0 - grabPassUV.y;
		
		depth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, grabPassUV), _ZBufferParams);
		depthDifference = depth - surfaceDepth;
		depthDifference = min(20, depthDifference);
	}
	float fogFactor = exp2(-_WaterFogDensity * depthDifference);
	fogFactor = saturate(fogFactor);

	//Get color below water
	float4 background = tex2D(_GrabbedTexture, grabPassUV);
	
	SurfaceData surfaceInput = (SurfaceData)0;
	surfaceInput.albedo = lerp(_WaterBottomColor, _WaterTopColor, fogFactor);
	if(foam > 0.1)
	{
		if( 1 - (_Time.y / 4 % (float)1.0) > foam && 1 - (_Time.y / 4 % (float)1.0) < foam + 0.5)
		{
			surfaceInput.emission = 2;
		}
		else
		{
			surfaceInput.emission = lerp(_WaterFogColor, background, fogFactor) * (1 - _BaseColor.a);
		}
	}
	else
	{
		surfaceInput.emission = lerp(_WaterFogColor, background, fogFactor) * (1 - _BaseColor.a);
	}
	//surfaceInput.emission = lerp(_WaterFogColor, background, fogFactor) * (1 - _BaseColor.a) * (1 - foam);
	surfaceInput.alpha = _BaseColor.a;
	surfaceInput.specular = 1;
	surfaceInput.smoothness = _Smoothness;
	surfaceInput.normalTS = float3(0, 0, 1);
	surfaceInput.normalTS = normalTS;

	InputData lightingInput = (InputData)0;
	InitializeInputData(input, surfaceInput.normalTS, lightingInput);
	
	return PBRLightingWater(lightingInput, surfaceInput);

#if UNITY_VERSION >= 202120
	return UniversalFragmentPBR(lightingInput, surfaceInput);
#else
	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput.albedo, float4(surfaceInput.specular, 1), surfaceInput.smoothness, surfaceInput.emission, surfaceInput.alpha);
#endif
}