#include <metal_stdlib>
using namespace metal;

struct DiscoUniforms {
    float time;
    float intensity;
    float colorVariation;
    float resolutionX;
    float resolutionY;
    float audioLevel;
    float bassLevel;
    float midLevel;
    float trebleLevel;
    float warpMagnitude;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                             constant float4* vertices [[buffer(0)]]) {
    VertexOut out;
    float4 vertexData = vertices[vertexID];
    out.position = float4(vertexData.xy, 0.0, 1.0);
    out.texCoord = vertexData.zw;
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                              texture2d<float> colorTexture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    return colorTexture.sample(textureSampler, in.texCoord);
}





kernel void discoShadowEffect(texture2d<float, access::read> inputTexture [[texture(0)]],
                             texture2d<float, access::write> outputTexture [[texture(1)]],
                             constant DiscoUniforms& uniforms [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }

    float2 uv = float2(gid) / float2(uniforms.resolutionX, uniforms.resolutionY);
    float2 centeredUV = uv * 2.0 - 1.0;

    // Audio-reactive warping
    float warpStrength = uniforms.warpMagnitude * (uniforms.bassLevel * 0.8 + uniforms.audioLevel * 0.3);
    float2 warpOffset = sin(centeredUV * 3.14159 + uniforms.time * 2.0) * warpStrength * 0.1;
    float2 warpedUV = uv + warpOffset;

    // Clamp UV coordinates
    warpedUV = clamp(warpedUV, 0.0, 1.0);
    uint2 warpedCoord = uint2(warpedUV * float2(uniforms.resolutionX, uniforms.resolutionY));

    // Sample base color with bounds checking
    float4 baseColor;
    if (warpedCoord.x < inputTexture.get_width() && warpedCoord.y < inputTexture.get_height()) {
        baseColor = inputTexture.read(warpedCoord);
    } else {
        baseColor = inputTexture.read(gid);
    }

    // Chromatic aberration effect
    float aberrationAmount = 0.015 * (1.0 + uniforms.trebleLevel * 2.0);
    float2 redOffset = float2(aberrationAmount, 0.0);
    float2 blueOffset = float2(-aberrationAmount, 0.0);

    uint2 redCoord = uint2(clamp(warpedUV + redOffset, 0.0, 1.0) * float2(uniforms.resolutionX, uniforms.resolutionY));
    uint2 blueCoord = uint2(clamp(warpedUV + blueOffset, 0.0, 1.0) * float2(uniforms.resolutionX, uniforms.resolutionY));

    float redChannel = baseColor.r;
    float blueChannel = baseColor.b;

    if (redCoord.x < inputTexture.get_width() && redCoord.y < inputTexture.get_height()) {
        redChannel = inputTexture.read(redCoord).r;
    }
    if (blueCoord.x < inputTexture.get_width() && blueCoord.y < inputTexture.get_height()) {
        blueChannel = inputTexture.read(blueCoord).b;
    }

    float3 chromaticColor = float3(redChannel, baseColor.g, blueChannel);

    // Glitch effect
    float glitchLine = floor(uv.y * 100.0 + uniforms.time * 30.0);
    float glitchNoise = fract(sin(glitchLine * 12.9898) * 43758.5453);
    float glitchMask = step(0.98, glitchNoise) * uniforms.intensity * 0.8;

    // Digital distortion
    float2 glitchOffset = float2(glitchMask * 0.1 * sin(uniforms.time * 10.0), 0.0);
    float2 glitchedUV = clamp(warpedUV + glitchOffset, 0.0, 1.0);
    uint2 glitchCoord = uint2(glitchedUV * float2(uniforms.resolutionX, uniforms.resolutionY));

    if (glitchMask > 0.0 && glitchCoord.x < inputTexture.get_width() && glitchCoord.y < inputTexture.get_height()) {
        chromaticColor = inputTexture.read(glitchCoord).rgb;
    }

    // Disco color enhancement
    float distance = length(centeredUV);
    float angle = atan2(centeredUV.y, centeredUV.x);

    // Color cycling based on audio
    float colorShift = uniforms.time * 2.0 + uniforms.midLevel * 4.0;
    float3 discoHue = float3(
        sin(colorShift + angle * 2.0) * 0.5 + 0.5,
        sin(colorShift + angle * 2.0 + 2.094) * 0.5 + 0.5,
        sin(colorShift + angle * 2.0 + 4.188) * 0.5 + 0.5
    );

    // Shadow/light patterns
    float shadowPattern = sin(distance * 8.0 + uniforms.time * 3.0) * 0.3 + 0.7;
    float audioReactivity = uniforms.audioLevel * uniforms.intensity;

    // Mix effects
    float3 finalColor = chromaticColor;
    finalColor = mix(finalColor, finalColor * discoHue, uniforms.colorVariation * audioReactivity);
    finalColor *= shadowPattern;

    // Audio-reactive brightness
    finalColor *= (1.0 + uniforms.bassLevel * 0.5);

    // Vignette effect
    float vignette = 1.0 - distance * 0.3;
    finalColor *= vignette;

    outputTexture.write(float4(finalColor, baseColor.a), gid);
}