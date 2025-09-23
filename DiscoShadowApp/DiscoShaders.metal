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

    // Only apply chromatic aberration if there's audio input - Enhanced with more movement
    if (uniforms.audioLevel > 0.01) {
        float aberrationAmount = 0.025 * (uniforms.audioLevel * 4.0 + uniforms.bassLevel * 3.0);

        // Add more dynamic movement patterns based on audio frequencies
        float bassMovement = sin(uniforms.time * 5.0) * uniforms.bassLevel * 0.8;
        float midMovement = cos(uniforms.time * 12.0) * uniforms.midLevel * 0.6;
        float trebleMovement = sin(uniforms.time * 20.0) * uniforms.trebleLevel * 0.4;

        // Create flowing circular motion for red channel (bass)
        float redAngle = uniforms.time * 3.0 + bassMovement * 2.0;
        float2 redOffset = aberrationAmount * float2(cos(redAngle), sin(redAngle)) * (1.0 + bassMovement);

        // Green channel gets subtle mid-frequency movement
        float2 greenOffset = float2(midMovement * 0.01, midMovement * 0.008);

        // Blue channel gets fast treble-driven movement
        float blueAngle = -uniforms.time * 4.0 + trebleMovement * 3.0;
        float2 blueOffset = aberrationAmount * float2(sin(blueAngle), cos(blueAngle)) * (1.0 + trebleMovement);

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


    // Add beat-reactive color intensity boosts to the existing chromatic colors
    float3 enhancedChromaticColor = chromaticColor;

    if (uniforms.audioLevel > 0.01) {
        // Convert to polar coordinates for additional effects
        float angle = atan2(centeredUV.y, centeredUV.x);
        float radius = length(centeredUV);

        // Add beat-reactive color intensity shifts to the aberration
        float beatPulse = sin(uniforms.time * 10.0) * uniforms.audioLevel * 0.2;
        float bassBoost = sin(uniforms.time * 6.0 + radius * 8.0) * uniforms.bassLevel * 0.3;
        float midBoost = sin(uniforms.time * 15.0 + angle * 6.0) * uniforms.midLevel * 0.25;
        float trebleBoost = sin(uniforms.time * 25.0 + (uv.x - uv.y) * 20.0) * uniforms.trebleLevel * 0.2;

        // Apply frequency-specific boosts to each color channel
        enhancedChromaticColor.r += bassBoost + beatPulse;
        enhancedChromaticColor.g += midBoost + beatPulse * 0.8;
        enhancedChromaticColor.b += trebleBoost + beatPulse * 0.6;

        enhancedChromaticColor = clamp(enhancedChromaticColor, 0.0, 1.0);
    }

    // Mix effects - focus on enhanced chromatic aberration as main effect
    float3 finalColor = enhancedChromaticColor;

    // Enhanced beat-reactive brightness and saturation
    float beatIntensity = uniforms.audioLevel * 1.2 + uniforms.bassLevel * 0.8;
    finalColor *= (1.0 + beatIntensity);

    // Beat-driven saturation boost
    float saturation = 1.0 + (uniforms.midLevel + uniforms.trebleLevel) * 0.6;
    float3 gray = float3(dot(finalColor, float3(0.299, 0.587, 0.114)));
    finalColor = mix(gray, finalColor, saturation);

    // Dynamic vignette that pulses with the beat
    float distance = length(centeredUV);
    float vignettePulse = 0.2 + sin(uniforms.time * 8.0) * uniforms.audioLevel * 0.1;
    float vignette = 1.0 - distance * vignettePulse;
    finalColor *= vignette;

    outputTexture.write(float4(finalColor, baseColor.a), gid);
}





