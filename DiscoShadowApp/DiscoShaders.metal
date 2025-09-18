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

    // Audio-reactive warping with base intensity
    float baseWarp = uniforms.warpMagnitude * 0.3; // Base warp always active
    float audioWarp = uniforms.warpMagnitude * (uniforms.bassLevel * 0.8 + uniforms.audioLevel * 0.5);
    float warpStrength = baseWarp + audioWarp;
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

    // Audio-reactive chromatic aberration effect - only when sound is present
    float3 chromaticColor = baseColor.rgb;

    // Only apply chromatic aberration if there's audio input
    if (uniforms.audioLevel > 0.01) {
        float aberrationAmount = 0.02 * (uniforms.audioLevel * 3.0 + uniforms.bassLevel * 2.0);
        float2 redOffset = float2(aberrationAmount * cos(uniforms.time), aberrationAmount * sin(uniforms.time * 0.7));
        float2 greenOffset = float2(0.0, 0.0);
        float2 blueOffset = float2(-aberrationAmount * sin(uniforms.time * 0.8), -aberrationAmount * cos(uniforms.time * 1.2));

        uint2 redCoord = uint2(clamp(warpedUV + redOffset, 0.0, 1.0) * float2(uniforms.resolutionX, uniforms.resolutionY));
        uint2 greenCoord = uint2(clamp(warpedUV + greenOffset, 0.0, 1.0) * float2(uniforms.resolutionX, uniforms.resolutionY));
        uint2 blueCoord = uint2(clamp(warpedUV + blueOffset, 0.0, 1.0) * float2(uniforms.resolutionX, uniforms.resolutionY));

        float redChannel = baseColor.r;
        float greenChannel = baseColor.g;
        float blueChannel = baseColor.b;

        if (redCoord.x < inputTexture.get_width() && redCoord.y < inputTexture.get_height()) {
            redChannel = inputTexture.read(redCoord).r;
        }
        if (greenCoord.x < inputTexture.get_width() && greenCoord.y < inputTexture.get_height()) {
            greenChannel = inputTexture.read(greenCoord).g;
        }
        if (blueCoord.x < inputTexture.get_width() && blueCoord.y < inputTexture.get_height()) {
            blueChannel = inputTexture.read(blueCoord).b;
        }

        chromaticColor = float3(redChannel, greenChannel, blueChannel);
    }


    // Audio-reactive color shaking - different frequencies affect different color channels
    float3 colorShake = chromaticColor;

    if (uniforms.audioLevel > 0.01) {
        // Bass affects red channel - slow, strong shaking
        float bassShake = sin(uniforms.time * 8.0 + uv.x * 20.0) * uniforms.bassLevel * 0.15;
        colorShake.r = clamp(colorShake.r + bassShake, 0.0, 1.0);

        // Mid frequencies affect green channel - medium speed shaking
        float midShake = sin(uniforms.time * 15.0 + uv.y * 30.0) * uniforms.midLevel * 0.12;
        colorShake.g = clamp(colorShake.g + midShake, 0.0, 1.0);

        // Treble affects blue channel - fast, subtle shaking
        float trebleShake = sin(uniforms.time * 25.0 + (uv.x + uv.y) * 40.0) * uniforms.trebleLevel * 0.1;
        colorShake.b = clamp(colorShake.b + trebleShake, 0.0, 1.0);

        // Overall audio level adds slight color intensity variation
        float overallShake = sin(uniforms.time * 12.0) * uniforms.audioLevel * 0.08;
        colorShake = clamp(colorShake + overallShake, 0.0, 1.0);
    }

    // Mix effects - focus on chromatic aberration and color shaking as main effects
    float3 finalColor = colorShake;

    // Audio-reactive brightness
    finalColor *= (1.0 + uniforms.bassLevel * 0.5);

    // Vignette effect
    float distance = length(centeredUV);
    float vignette = 1.0 - distance * 0.3;
    finalColor *= vignette;

    outputTexture.write(float4(finalColor, baseColor.a), gid);
}