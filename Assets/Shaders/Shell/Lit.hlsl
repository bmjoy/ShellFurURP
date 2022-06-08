#ifndef FUR_SHELL_LIT_HLSL
#define FUR_SHELL_LIT_HLSL

#include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
#include "./Param.hlsl"
#include "./Common.hlsl"
#if defined(_FUR_SPECULAR)
#include "./FurSpecular.hlsl"
#endif
// VR single pass instance compability:
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 texcoord : TEXCOORD0;
    float2 staticLightmapUV : TEXCOORD1;
    float2 dynamicLightmapUV : TEXCOORD2; // Dynamic lightmap UVs
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct v2g
{
    float4 positionOS : POSITION;
    float3 normalWS : NORMAL;
    float3 tangentWS : TANGENT;
    float2 texcoord : TEXCOORD0;
    float2 staticLightmapUV : TEXCOORD1;
#ifdef DYNAMICLIGHTMAP_ON
    float2  dynamicLightmapUV : TEXCOORD2;
#endif
    float3 groomWS : TEXCOORD3;
    float furLength : TEXCOORD4;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct g2f
{
    float4 positionCS : SV_POSITION;
    float3 positionWS : TEXCOORD0;
    float3 normalWS : TEXCOORD1;
    float3 tangentWS : TEXCOORD2;
    float2 uv : TEXCOORD4;
    DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 5);
    float fogFactor : TEXCOORD6;
    float  layer : TEXCOORD7;
#ifdef DYNAMICLIGHTMAP_ON
    float2  dynamicLightmapUV : TEXCOORD8;
#endif
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

v2g vert(Attributes input)
{
    v2g output = (v2g)0;
    // setup the instanced id
    UNITY_SETUP_INSTANCE_ID(input);
    // set all values in the "v2g output" to 0.0
    // This is the URP version of UNITY_INITIALIZE_OUTPUT()
    ZERO_INITIALIZE(v2g, output);
    // copy instance id in the "Attributes input" to the "v2g output"
    UNITY_TRANSFER_INSTANCE_ID(input, output);

    VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

    // Fur Direction and Length (reusable data for geometry shader)
    float3 groomTS = SafeNormalize(UnpackNormal(SAMPLE_TEXTURE2D_LOD(_FurDirMap, sampler_FurDirMap, input.texcoord / _BaseMap_ST.xy, 0).xyzw));

    output.groomWS = SafeNormalize(TransformTangentToWorld(
        groomTS,
        float3x3(normalInput.tangentWS, normalInput.bitangentWS, normalInput.normalWS)));

    output.furLength = SAMPLE_TEXTURE2D_LOD(_FurLengthMap, sampler_FurLengthMap, input.texcoord / _BaseMap_ST.xy, 0).x;

    output.positionOS = input.positionOS;
    output.normalWS = normalInput.normalWS;
    output.tangentWS = normalInput.tangentWS;
    output.texcoord = input.texcoord;
    output.staticLightmapUV = input.staticLightmapUV;
#ifdef DYNAMICLIGHTMAP_ON
    output.dynamicLightmapUV = input.dynamicLightmapUV.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
#endif
    return output;
}

void AppendShellVertex(inout TriangleStream<g2f> stream, v2g input, int index)
{
    g2f output = (g2f)0;
    UNITY_SETUP_INSTANCE_ID(input);
    // set all values in the g2f output to 0.0
    ZERO_INITIALIZE(g2f, output);

    UNITY_TRANSFER_INSTANCE_ID(input, output);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);

    float clampedShellAmount = clamp(_ShellAmount, 1, 13);
    _ShellStep = _TotalShellStep / clampedShellAmount;

    float moveFactor = pow(abs((float)index / clampedShellAmount), _BaseMove.w);
    float3 posOS = input.positionOS.xyz;
    float3 windAngle = _Time.w * _WindFreq.xyz;
    float3 windMove = moveFactor * _WindMove.xyz * sin(windAngle + posOS * _WindMove.w);
    float3 move = moveFactor * _BaseMove.xyz;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Fur Direction
    float layer = (float)index / clampedShellAmount;

    float bent = _BentType * layer + (1 - _BentType);

    float3 groomWS = lerp(input.normalWS, input.groomWS, _GroomingIntensity * bent);
    float3 shellDir = SafeNormalize(groomWS + move + windMove);
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    output.positionWS = vertexInput.positionWS + shellDir * (_ShellStep * index * input.furLength * _FurLengthIntensity);
    output.positionCS = TransformWorldToHClip(output.positionWS);
    output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
    output.normalWS = input.normalWS;
    output.tangentWS = input.tangentWS;
    output.layer = layer;

    output.fogFactor = 0;
#if !defined(_FOG_FRAGMENT)
    output.fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
#endif

    OUTPUT_LIGHTMAP_UV(input.staticLightmapUV, unity_LightmapST, output.staticLightmapUV);
#ifdef DYNAMICLIGHTMAP_ON
    output.dynamicLightmapUV = input.dynamicLightmapUV;
#endif
    OUTPUT_SH(output.normalWS.xyz, output.vertexSH);


    stream.Append(output);
}

// For geometry shader instancing, no clamp on _ShellAmount.
void AppendShellVertexInstancing(inout TriangleStream<g2f> stream, v2g input, int index)
{
    g2f output = (g2f)0;
    UNITY_SETUP_INSTANCE_ID(input);
    // set all values in the g2f output to 0.0
    ZERO_INITIALIZE(g2f, output);

    UNITY_TRANSFER_INSTANCE_ID(input, output);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);

    _ShellStep = _TotalShellStep / _ShellAmount;

    float moveFactor = pow(abs((float)index / _ShellAmount), _BaseMove.w);
    float3 posOS = input.positionOS.xyz;
    float3 windAngle = _Time.w * _WindFreq.xyz;
    float3 windMove = moveFactor * _WindMove.xyz * sin(windAngle + posOS * _WindMove.w);
    float3 move = moveFactor * _BaseMove.xyz;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Fur Direction
    float layer = (float)index / _ShellAmount;

    float bent = _BentType * layer + (1 - _BentType);

    float3 groomWS = lerp(input.normalWS, input.groomWS, _GroomingIntensity * bent);
    float3 shellDir = SafeNormalize(groomWS + move + windMove);
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    output.positionWS = vertexInput.positionWS + shellDir * (_ShellStep * index * input.furLength * _FurLengthIntensity);
    output.positionCS = TransformWorldToHClip(output.positionWS);
    output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
    output.normalWS = input.normalWS;
    output.tangentWS = input.tangentWS;
    output.layer = layer;

    output.fogFactor = 0;
#if !defined(_FOG_FRAGMENT)
    output.fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
#endif

    OUTPUT_LIGHTMAP_UV(input.staticLightmapUV, unity_LightmapST, output.staticLightmapUV);
#ifdef DYNAMICLIGHTMAP_ON
    output.dynamicLightmapUV = input.dynamicLightmapUV;
#endif
    OUTPUT_SH(output.normalWS.xyz, output.vertexSH);


    stream.Append(output);
}

//-----------------------------------(below) For Microsoft Shader Model > 4.1-----------------------------------
// "[instance(3)]" = 3+1 geometry shader instances, so we can have at most 13x4 = 52 shells
//
// If you need 200 shells (too much for game):
// "200 / 13 = 15, remains 5"
// 
// You will need "16" instances, "15" for 195 shells, "1" for 5 remaining shells.
// So, use [instance(15)] to execute "15+1" instances.
// 
// IMPORTANT: if you set [instance(30)] for 200 shells, you will waste performance because
//            "stream.RestartStrip()" will run on 14 istances (with empty output).
// 
//            Please keep "n" in [instance(n)] the same for all "passes.hlsl" (Lit, Depth, DepthNormals, Shadow, LitGBuffer...)
//            Or something will break! (post-processing in most cases)
// 
// LIMIT: You can only have up to 32 instances, so (32+1)x13 = 429 shells at most.
#if defined(_GEOM_INSTANCING)
[instance(3)]
[maxvertexcount(39)]
void geom(triangle v2g input[3], inout TriangleStream<g2f> stream, uint instanceID : SV_GSInstanceID)
{
    // 13 is calculated manually, because "maxvertexcount" is 39 in "Lit.hlsl", keep all passes to have the smallest (39 now).
    // If not, DepthNormals will be incorrect and Depth Priming (DepthNormal Mode) won't work.
    // "39 / 3 = 13", 3 means 3 vertices of a tirangle.
    [loop] for (float i = 0 + (instanceID * 13); i < _ShellAmount; ++i)
    {
        [unroll] for (float j = 0; j < 3; ++j)
        {
            AppendShellVertexInstancing(stream, input[j], i);
        }
        stream.RestartStrip();
    }
}
//-----------------------------------(above) For Microsoft Shader Model > 4.1-----------------------------------

//-----------------------------------(below) For Microsoft Shader Model < 4.1-----------------------------------
// For device that does not support geometry shader instancing.
// Available since Microsoft Shader Model 4.1, it is "target 4.6" in Unity.
#else
[maxvertexcount(39)]
void geom(triangle v2g input[3], inout TriangleStream<g2f> stream)
{
    [loop] for (float i = 0; i < clamp(_ShellAmount, 1, 13); ++i)
    {
        [unroll] for (float j = 0; j < 3; ++j)
        {
            AppendShellVertex(stream, input[j], i);
        }
        stream.RestartStrip();
    }
}
#endif
//-----------------------------------(above) For Microsoft Shader Model < 4.1-----------------------------------

half4 frag(g2f input) : SV_Target
{
    float2 furUv = input.uv / _BaseMap_ST.xy * _FurScale;
    float4 furColor = SAMPLE_TEXTURE2D(_FurMap, sampler_FurMap, furUv);
    float alpha = furColor.r * (1.0 - input.layer);
    if (input.layer > 0.0 && alpha < _AlphaCutout) discard;

    float3 viewDirWS = SafeNormalize(GetCameraPositionWS() - input.positionWS);
    float3 normalTS = UnpackNormalScale(
        SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, furUv), 
        _NormalScale);
    // 1.0 should be tangentOS.w, not passing it to fragment shader to keep 39 max vertex counts.
    float3 bitangent = SafeNormalize(1.0 * cross(input.normalWS, input.tangentWS));
    float3 normalWS = SafeNormalize(TransformTangentToWorld(
        normalTS, 
        float3x3(input.tangentWS, bitangent, input.normalWS)));

    SurfaceData surfaceData = (SurfaceData)0;
    InitializeStandardLitSurfaceData(input.uv, surfaceData);
    half AO = (1.0-SAMPLE_TEXTURE2D(_AOMap, sampler_AOMap, input.uv / _BaseMap_ST.xy).x)* _Occlusion;
    surfaceData.occlusion = (1.0 - AO) * lerp(1.0 - _Occlusion* _Occlusion, 1.0, input.layer);

    InputData inputData = (InputData)0;
    inputData.positionWS = input.positionWS;
    inputData.normalWS = normalWS;
    inputData.viewDirectionWS = viewDirWS;
#if defined(_MAIN_LIGHT_SHADOWS) || defined(_MAIN_LIGHT_SHADOWS_CASCADE) || defined(_MAIN_LIGHT_SHADOWS_SCREEN) && !defined(_RECEIVE_SHADOWS_OFF)
    inputData.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
#else
    inputData.shadowCoord = half4(0, 0, 0, 0);
#endif
    inputData.fogCoord = input.fogFactor;

#ifdef _ADDITIONAL_LIGHTS_VERTEX
    // Vertex Lighting will not be supported as it is not fast enough when calculating so many vertices (in geometry shader).

    inputData.vertexLighting = half3(0, 0, 0);
    //inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;
#endif

#if defined(DYNAMICLIGHTMAP_ON)
    inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.dynamicLightmapUV, input.vertexSH, inputData.normalWS);
#else
    inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.vertexSH, inputData.normalWS);
#endif

    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
    inputData.shadowMask = SAMPLE_SHADOWMASK(input.staticLightmapUV);

    SETUP_DEBUG_TEXTURE_DATA(inputData, input.uv, _BaseMap);

#ifdef _DBUFFER
    ApplyDecalToSurfaceData(input.positionCS, surfaceData, inputData);
#endif

    half4 color = UniversalFragmentPBR(inputData, surfaceData);

#if defined(_FUR_SPECULAR) && !defined(DEBUG_DISPLAY)
    // Use abs(f) to avoid warning messages that f should not be negative in pow(f, e).
    SurfaceOutputFur s = (SurfaceOutputFur)0;
    s.Albedo = abs(surfaceData.albedo * _BaseColor.rgb);
    s.MedulaScatter = abs(_MedulaScatter);
    s.MedulaAbsorb = abs(1.0 - _MedulaAbsorb);
    // Convert smoothness to roughness, (1 - smoothness) is perceptual roughness.
    s.Roughness = (1.0 - _FurSmoothness) * (1.0 - _FurSmoothness);
    s.Layer = input.layer;
    s.Kappa = (1.0 - _Kappa / 2.0);

    Light mainLight = GetMainLight();
    uint meshRenderingLayers = GetMeshRenderingLightLayer();
#ifdef _LIGHT_LAYERS
    if (IsMatchingLightLayer(mainLight.layerMask, meshRenderingLayers))
#endif
    {
        half3 mainLightColor = mainLight.color.rgb * mainLight.distanceAttenuation;
        // "Screen" blend mode.
        mainLightColor = (1 - (1 - s.Albedo) * (1 - mainLightColor));
        color.rgb += (mainLightColor * FurBSDFYan(s, mainLight.direction, viewDirWS, normalWS, 1.0, _Backlit, _Area));

    }

    // Calculate additional lights.
#ifdef _ADDITIONAL_LIGHTS
    int additionalLightsCount = GetAdditionalLightsCount();
    for (int i = 0; i < additionalLightsCount; ++i)
    {
        int index = GetPerObjectLightIndex(i);
        Light light = GetAdditionalPerObjectLight(index, input.positionWS);
#ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
#endif
        {
            half3 lightColor = light.color.rgb * light.distanceAttenuation;
            // "Screen" blend mode.
            lightColor = (1 - (1 - s.Albedo) * (1 - lightColor));
            color.rgb += (lightColor * FurBSDFYan(s, light.direction, viewDirWS, normalWS, 1.0, _Backlit, _Area));
        }
    }
#endif

    color.rgb = -min(-color.rgb, half3(0.0, 0.0, 0.0));
#endif

#if !defined(DEBUG_DISPLAY)
    ApplyRimLight(color.rgb, input.positionWS, viewDirWS, normalWS);
#endif

    color.rgb = MixFog(color.rgb, inputData.fogCoord);

    return color;
}

#endif
