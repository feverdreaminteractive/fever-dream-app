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
    float glitchIntensity;
    float chromaticAberration;
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
    if (uniforms.audioLevel > 0.001) {
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

    if (uniforms.audioLevel > 0.001) {
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

// MARK: - CRT Dither Glitch Effect (Premium)
kernel void crtDitherGlitchEffect(texture2d<float, access::read> inputTexture [[texture(0)]],
                                  texture2d<float, access::write> outputTexture [[texture(1)]],
                                  constant DiscoUniforms &uniforms [[buffer(0)]],
                                  uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }

    float2 uv = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    float4 inputColor = inputTexture.read(gid);

    // Audio responsiveness
    float audioReactivity = (uniforms.audioLevel * 2.0 + uniforms.bassLevel * 3.0) * uniforms.intensity;
    audioReactivity = clamp(audioReactivity, 0.0, 1.0);

    // Time-based effects
    float time = uniforms.time * 0.5;

    // === SCAN LINES === (Bigger scanlines)
    float scanlineFreq = 200.0 + audioReactivity * 100.0;
    float scanlines = sin(uv.y * scanlineFreq) * 0.5 + 0.5;
    scanlines = smoothstep(0.3, 0.7, scanlines);

    // === RGB PHOSPHOR PATTERN ===
    float2 phosphorUV = uv * float2(outputTexture.get_width() / 3.0, outputTexture.get_height());
    float phosphorPattern = fmod(phosphorUV.x, 3.0);

    float3 phosphorMask = float3(1.0);
    if (phosphorPattern < 1.0) {
        phosphorMask = float3(1.0, 0.3, 0.3); // Red phosphor
    } else if (phosphorPattern < 2.0) {
        phosphorMask = float3(0.3, 1.0, 0.3); // Green phosphor
    } else {
        phosphorMask = float3(0.3, 0.3, 1.0); // Blue phosphor
    }

    // === DITHERING PATTERN ===
    // Bayer matrix 4x4 for ordered dithering (simplified for performance)
    int x = int(gid.x) % 4;
    int y = int(gid.y) % 4;

    float bayerMatrix[16] = {
         0,  8,  2, 10,
        12,  4, 14,  6,
         3, 11,  1,  9,
        15,  7, 13,  5
    };

    float ditherThreshold = bayerMatrix[y * 4 + x] / 16.0;
    ditherThreshold += audioReactivity * 0.3; // Audio-reactive dithering

    // === GLITCH EFFECTS ===
    float glitchNoise = fract(sin(dot(uv + time, float2(12.9898, 78.233))) * 43758.5453);
    float glitchIntensity = uniforms.glitchIntensity * audioReactivity;

    // Horizontal glitch displacement
    float glitchLine = step(0.98, glitchNoise) * glitchIntensity;
    float displacement = (glitchNoise - 0.5) * glitchLine * 0.1;
    uv.x += displacement;

    // Digital noise
    float digitalNoise = step(0.95, fract(sin(dot(float2(gid), float2(12.9898, 78.233)) + time) * 43758.5453));
    digitalNoise *= glitchIntensity;

    // Sample the input texture with glitch displacement
    uint2 sampleCoord = uint2(clamp(uv * float2(inputTexture.get_width(), inputTexture.get_height()),
                                   float2(0.0),
                                   float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1)));

    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        inputColor = float4(0.0, 0.0, 0.0, 1.0); // Black outside bounds
    } else {
        inputColor = inputTexture.read(sampleCoord);
    }

    // === COLOR PROCESSING ===
    float3 color = inputColor.rgb;

    // Convert to CRT-style colors (boost greens for that retro monitor look)
    color.g *= 1.2;
    color.r *= 0.9;
    color.b *= 0.8;

    // Apply dithering
    float brightness = dot(color, float3(0.299, 0.587, 0.114));
    if (brightness < ditherThreshold) {
        color *= 0.3; // Darken dithered areas
    }

    // Apply phosphor mask
    color *= phosphorMask;

    // Apply scanlines
    color *= scanlines * 0.7 + 0.3;

    // Add digital noise
    color += digitalNoise * float3(0.1, 1.0, 0.1); // Green noise for CRT feel

    // === CHROMATIC ABERRATION ===
    float aberrationAmount = uniforms.chromaticAberration + audioReactivity * 0.02;
    if (aberrationAmount > 0.001) {
        float2 redOffset = float2(-aberrationAmount, 0.0);
        float2 blueOffset = float2(aberrationAmount, 0.0);

        uint2 redCoord = uint2(clamp((uv + redOffset) * float2(inputTexture.get_width(), inputTexture.get_height()),
                                    float2(0.0),
                                    float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1)));
        uint2 blueCoord = uint2(clamp((uv + blueOffset) * float2(inputTexture.get_width(), inputTexture.get_height()),
                                     float2(0.0),
                                     float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1)));

        color.r = inputTexture.read(redCoord).r * phosphorMask.r;
        color.b = inputTexture.read(blueCoord).b * phosphorMask.b;
    }

    // Final color adjustments for CRT look
    color = saturate(color);
    color = pow(color, float3(1.0/2.2)); // Gamma correction for CRT

    // Add subtle flicker
    float flicker = 0.95 + 0.05 * sin(time * 60.0 + audioReactivity * 10.0);
    color *= flicker;

    float4 outputColor = float4(color, inputColor.a);
    outputTexture.write(outputColor, gid);
}

// MARK: - VHS Datamoshing Effect (Premium) - Bad TV Glitch Version
kernel void crtSlitScanEffect(texture2d<float, access::read> inputTexture [[texture(0)]],
                              texture2d<float, access::write> outputTexture [[texture(1)]],
                              constant DiscoUniforms &uniforms [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }

    float2 uv = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    float4 inputColor = inputTexture.read(gid);

    // Center the UV coordinates for proper centering (0.5, 0.5 is center)
    float2 centeredUV = uv - 0.5;

    // Enhanced audio responsiveness with frequency separation
    float bassReactivity = uniforms.bassLevel * uniforms.intensity * 3.0; // Increased for more aggressive response
    float midReactivity = uniforms.midLevel * uniforms.intensity * 2.5;
    float trebleReactivity = uniforms.trebleLevel * uniforms.intensity * 2.0;
    float totalAudio = uniforms.audioLevel * uniforms.intensity * 3.5;

    // Create different strength levels for different effects
    float shakeStrength = clamp(bassReactivity + totalAudio * 1.2, 0.0, 1.5); // Allow stronger effects
    float glitchStrength = clamp(midReactivity + totalAudio * 1.0, 0.0, 1.5);
    float noiseStrength = clamp(trebleReactivity + totalAudio * 0.8, 0.0, 1.0);

    // Time-based effects with audio modulation - ensure no base offset
    float time = uniforms.time + totalAudio * 15.0;

    // === SHAKE EFFECT - REMOVED ===
    // Shake effect removed to eliminate remaining distortion lines
    float2 shake = float2(0.0, 0.0);

    // === PROMINENT WAVY DISTORTION - Main VHS Effect ===
    // Strong, always-visible wavy distortion as the primary effect
    float y = centeredUV.y * float(outputTexture.get_height());
    float audioMultiplier = smoothstep(0.1, 0.5, totalAudio); // Audio enhancement multiplier

    // ORGANIC base wavy distortion - smooth and flowing
    // Create gentle, organic phase variations that change very slowly
    float organicPhase1 = sin(time * 0.08) * 2.0;  // Very slow organic drift
    float organicPhase2 = cos(time * 0.12) * 1.5;  // Another slow drift
    float organicPhase3 = sin(time * 0.06) * 1.8;  // Even slower variation

    float baseWave = (
        sin(y * 0.0015 + time * 0.6 + organicPhase1) * 5.0 +        // Large, slow primary wave
        cos(y * 0.003 + time * 0.8 + organicPhase2) * 3.0 +         // Gentle secondary wave
        sin(y * 0.005 + time * 0.4 + organicPhase3) * 1.5           // Subtle detail wave
        // Removed complex modulations and high-frequency components
    ) / float(outputTexture.get_width());

    // Audio-enhanced waves - randomized for variety
    float audioRandomSeed1 = sin(time * 0.31 + totalAudio * 10.0) * 29.176;
    float audioRandomSeed2 = cos(time * 0.37 + totalAudio * 15.0) * 51.234;

    float audioWave = (
        sin(y * 0.003 + time * 2.0 + audioRandomSeed1) * (glitchStrength * 35.0 * audioMultiplier) +
        cos(y * 0.006 + time * 1.8 + audioRandomSeed2) * sin(y * 0.005 + time * 2.2) * (glitchStrength * 20.0 * audioMultiplier)
        // Smooth randomized audio waves
    ) / float(outputTexture.get_width());

    float rgbWave = baseWave + audioWave;

    // INTENSE chromatic aberration with randomized patterns
    float chromaticRandomSeed = sin(time * 0.19) * 67.891;
    float baseChromaticAberration = 6.0 / float(outputTexture.get_width()); // Much more noticeable base
    float wavyChromaticAberration = (sin(y * 0.004 + time * 1.0 + chromaticRandomSeed) + cos(y * 0.003 + time * 0.9)) * 2.0 / float(outputTexture.get_width()); // Randomized wave-based aberration
    float audioChromaticAberration = sin(time * 25.0 + centeredUV.y * 20.0 + totalAudio * 50.0) * (35.0 * glitchStrength * audioMultiplier) / float(outputTexture.get_width());
    float rgbDiff = baseChromaticAberration + wavyChromaticAberration + audioChromaticAberration;

    // === AUDIO-TRIGGERED XY SHAKE ===
    float2 xyShake = float2(0.0, 0.0);

    if (totalAudio > 0.05) {  // Audio threshold for shake
        // X-axis shake based on bass frequencies
        float xShakeStrength = bassReactivity * 0.015;  // Adjust shake intensity
        xyShake.x = (sin(time * 60.0 + bassReactivity * 100.0) * xShakeStrength);

        // Y-axis shake based on treble frequencies
        float yShakeStrength = trebleReactivity * 0.012;  // Adjust shake intensity
        xyShake.y = (cos(time * 75.0 + trebleReactivity * 120.0) * yShakeStrength);

        // Add overall audio shake for more intensity
        float overallShakeStrength = totalAudio * 0.008;
        xyShake.x += sin(time * 45.0 + totalAudio * 80.0) * overallShakeStrength;
        xyShake.y += cos(time * 55.0 + totalAudio * 90.0) * overallShakeStrength;
    }

    // Apply XY shake to UV coordinates for sampling
    float2 displacedUV = uv + xyShake;
    displacedUV = clamp(displacedUV, float2(0.0), float2(1.0));

    float rgbUvX = uv.x + rgbWave; // Apply displacement to original UV for sampling

    // === SIGNAL DROPOUT EFFECT - REMOVED ===
    // Signal dropout removed to eliminate any remaining slit scan artifacts
    float signalDropout = 0.0;

    // === CHROMATIC ABERRATION with RGB SEPARATION ===
    // Sample RGB channels with different offsets - pure chromatic aberration only
    // Apply XY displacement to the base coordinates
    float2 centeredRGBBase = displacedUV;

    uint2 redCoord = uint2(clamp((centeredRGBBase + float2(rgbDiff, 0.0)) * float2(inputTexture.get_width(), inputTexture.get_height()),
                                 float2(0.0),
                                 float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1)));
    uint2 greenCoord = uint2(clamp(centeredRGBBase * float2(inputTexture.get_width(), inputTexture.get_height()),
                                   float2(0.0),
                                   float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1)));
    uint2 blueCoord = uint2(clamp((centeredRGBBase + float2(-rgbDiff, 0.0)) * float2(inputTexture.get_width(), inputTexture.get_height()),
                                  float2(0.0),
                                  float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1)));

    float r = inputTexture.read(redCoord).r;
    float g = inputTexture.read(greenCoord).g;
    float b = inputTexture.read(blueCoord).b;

    // === WHITE NOISE - REMOVED ===
    // White noise removed for cleaner wave effect
    float whiteNoise = 0.0;

    // === BLOCK NOISE LAYERS - REMOVED ===
    // Block noise layers removed to eliminate horizontal slit lines
    float bnMask = 0.0;
    float bnMask2 = 0.0;
    float3 blockNoise = float3(0.0);
    float3 blockNoise2 = float3(0.0);

    // === WAVE NOISE - REMOVED ===
    // Wave noise removed to eliminate horizontal slit line patterns
    float waveNoise = 0.0;

    // === ROLLING INTERFERENCE - REMOVED ===
    // Rolling bars removed for cleaner wave-focused effect
    float rollingBar = 0.0;

    // === INTERLACED FIELD EFFECT - REMOVED ===
    // Field corruption removed for pure wave effect
    float fieldCorruption = 0.0;

    // === FINAL BAD TV COMPOSITE ===
    // Combine all effects
    float3 baseColor = float3(r, g, b);

    // Signal dropout removed
    // baseColor = baseColor; // No dropout effect

    // Apply composite with pure wavy distortion - no texture noise
    float3 finalColor = baseColor; // Pure clean wavy distortion only

    // Scanlines removed - no more CRT scan lines
    // float scanlines = 1.0; // No scanline effect

    // Enhanced color grading - keep more saturation for intense wave colors
    float luminance = dot(finalColor, float3(0.299, 0.587, 0.114));
    finalColor = mix(float3(luminance), finalColor, 0.85); // Keep more color saturation
    finalColor *= float3(1.15, 0.95, 0.9); // Enhance color intensity

    // Static snow removed - focus on wave effects
    // float snow = 0.0; // No longer needed

    // Enhanced flutter with randomized rhythm - use centered coordinates
    float flutterRandomSeed = cos(time * 0.07) * 91.257;
    float flutter = (sin(time * 6.0 + centeredUV.y * 25.0 + flutterRandomSeed) + cos(time * 5.5 + centeredUV.y * 22.0)) * 0.025 * totalAudio;
    finalColor += float3(flutter * 0.20, flutter * 0.10, flutter * -0.10); // More intense color flutter

    // === INTENSITY FADE-OUT EFFECT ===
    // Create a breathing/pulsing effect by modulating the effect intensity instead of alpha
    float breatheCycle = sin(time * 0.4) * 0.5 + 0.5; // Slow breathing cycle (0 to 1)
    float fadeOut = smoothstep(0.3, 0.7, breatheCycle); // Smooth fade transition

    // Add audio-reactive breathing
    float audioBreathe = smoothstep(0.1, 0.8, totalAudio) * 0.3; // Audio affects breathing intensity
    fadeOut = mix(fadeOut, 1.0, audioBreathe); // Less fade-out during audio

    // === GEOMETRIC VHS COLOR TRAILING EFFECTS ===
    // Add visible geometric trailing color effects with sharp, blocky appearance
    if (totalAudio > 0.08) {  // Lower threshold - more responsive
        // 6 trails for good visibility without overwhelming
        for (int i = 1; i <= 6; i++) {
            float trail_factor = float(i);
            float trail_decay = 1.0 - (trail_factor / 6.0);

            // Horizontal trailing (classic VHS effect) - sharp geometric with shake
            float2 trail_uv = float2(float(gid.x) - i * (2 + int(bassReactivity * 2.0)), float(gid.y)) /
                              float2(inputTexture.get_width(), inputTexture.get_height());
            trail_uv += xyShake;  // Apply shake to trail sampling
            trail_uv = clamp(trail_uv, float2(0.0), float2(1.0));

            uint2 trail_pos = uint2(trail_uv * float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1));
            if (trail_pos.x < inputTexture.get_width() && trail_pos.y < inputTexture.get_height()) {
                float3 trail_color = inputTexture.read(trail_pos).rgb;

                // Balanced trail strength - visible but not overwhelming
                float trail_strength = trail_decay * (bassReactivity * 1.0 + totalAudio * 0.5) * 0.8;

                // Fast strobing color shifting with more colors
                float hue_shift = trail_factor * 1.2 + time * 8.0 + bassReactivity * 12.0;  // Much faster

                // Create multiple color layers for richer color palette
                float3 color_shift_1 = float3(
                    sin(hue_shift) * 0.45,
                    sin(hue_shift + 2.094) * 0.45,  // 120 degrees
                    sin(hue_shift + 4.188) * 0.45   // 240 degrees
                );

                float3 color_shift_2 = float3(
                    cos(hue_shift * 1.3 + 1.0) * 0.35,  // Different frequency and phase
                    cos(hue_shift * 1.3 + 3.094) * 0.35,
                    cos(hue_shift * 1.3 + 5.188) * 0.35
                );

                float3 color_shift_3 = float3(
                    sin(hue_shift * 0.7 + 2.5) * 0.25,  // Slower harmonic
                    sin(hue_shift * 0.7 + 4.5) * 0.25,
                    sin(hue_shift * 0.7 + 6.5) * 0.25
                );

                // Combine all color layers for rich, fast-strobing colors
                float3 color_shift = color_shift_1 + color_shift_2 + color_shift_3;

                // Balanced mixing with sharp geometric sampling
                trail_color += color_shift * trail_strength;
                finalColor = mix(finalColor, trail_color, trail_strength * 0.25);  // Visible contribution
            }

            // Add vertical trails for treble with sharp geometric edges and shake
            if (trebleReactivity > 0.3) {
                float2 vert_trail_uv = float2(float(gid.x), float(gid.y) - i * 2) /
                                      float2(inputTexture.get_width(), inputTexture.get_height());
                vert_trail_uv += xyShake;  // Apply shake to vertical trail sampling
                vert_trail_uv = clamp(vert_trail_uv, float2(0.0), float2(1.0));

                uint2 trail_pos = uint2(vert_trail_uv * float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1));
                if (trail_pos.x < inputTexture.get_width() && trail_pos.y < inputTexture.get_height()) {
                    float3 trail_color = inputTexture.read(trail_pos).rgb;

                    float trail_strength = trail_decay * trebleReactivity * 0.6;

                    // Fast strobing colors for vertical trails
                    float vert_hue = time * 10.0 + trebleReactivity * 15.0 + trail_factor * 2.0;
                    trail_color.b += trail_strength * (0.4 + sin(vert_hue) * 0.3);
                    trail_color.r += trail_strength * (0.2 + cos(vert_hue * 1.4) * 0.25);
                    trail_color.g += trail_strength * (sin(vert_hue * 0.8 + 1.5) * 0.15);

                    finalColor = mix(finalColor, trail_color, trail_strength * 0.15);
                }
            }

            // Add diagonal trails for mid frequencies - creates geometric grid pattern with shake
            if (midReactivity > 0.25) {
                float2 diag_trail_uv = float2(float(gid.x) - i * 1, float(gid.y) - i * 1) /
                                      float2(inputTexture.get_width(), inputTexture.get_height());
                diag_trail_uv += xyShake;  // Apply shake to diagonal trail sampling
                diag_trail_uv = clamp(diag_trail_uv, float2(0.0), float2(1.0));

                uint2 trail_pos = uint2(diag_trail_uv * float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1));
                if (trail_pos.x < inputTexture.get_width() && trail_pos.y < inputTexture.get_height()) {
                    float3 trail_color = inputTexture.read(trail_pos).rgb;

                    float trail_strength = trail_decay * midReactivity * 0.5;

                    // Fast strobing rainbow colors for diagonal trails
                    float diag_hue = time * 12.0 + midReactivity * 18.0 + trail_factor * 3.0;
                    trail_color.r += trail_strength * (0.4 + sin(diag_hue) * 0.4);
                    trail_color.g += trail_strength * (0.6 + sin(diag_hue + 2.0) * 0.5);
                    trail_color.b += trail_strength * (0.3 + sin(diag_hue + 4.0) * 0.35);

                    finalColor = mix(finalColor, trail_color, trail_strength * 0.2);
                }
            }
        }

        // Moderate brightness boost during trailing
        finalColor *= (1.0 + totalAudio * 0.2);
    }

    // Apply fade-out to effect intensity, not alpha
    float effectIntensity = 0.4 + fadeOut * 0.6; // Intensity varies between 40% and 100%
    finalColor = mix(inputColor.rgb, finalColor, effectIntensity); // Blend between original and effect

    // Clamp to valid range and output with original alpha
    finalColor = saturate(finalColor);
    float4 outputColor = float4(finalColor, inputColor.a);
    outputTexture.write(outputColor, gid);
}

// MARK: - Atari 1977 Retro Effect (Premium)
kernel void atari1977RetroEffect(texture2d<float, access::read> inputTexture [[texture(0)]],
                                texture2d<float, access::write> outputTexture [[texture(1)]],
                                constant DiscoUniforms &uniforms [[buffer(0)]],
                                uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }

    float2 uv = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    float4 inputColor = inputTexture.read(gid);

    // Audio reactivity factor
    float audioReactivity = (uniforms.bassLevel + uniforms.midLevel + uniforms.trebleLevel) / 3.0;
    float time = uniforms.time;

    // === ATARI 1977 RETRO COMPUTER GRAPHICS STYLE ===
    // Inspired by the pixelmusic3000 hardware schematic

    // Pixelation - create blocky retro look like composite video output
    float pixelSize = 48.0 + audioReactivity * 16.0; // Fine pixels for excellent image recognition
    float2 pixelUV = floor(uv * pixelSize) / pixelSize;

    // Sample video with pixelated coordinates
    uint2 pixelCoord = uint2(clamp(pixelUV * float2(inputTexture.get_width(), inputTexture.get_height()),
                                   float2(0.0),
                                   float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1)));
    float3 pixelColor = inputTexture.read(pixelCoord).rgb;

    // === RETRO COLOR PALETTE (1977 CRT Monitor/Composite Video Style) ===
    // Reduce to limited color palette like Propeller chip output
    float luma = dot(pixelColor, float3(0.299, 0.587, 0.114));

    // Quantize to 4 color levels like early computers
    float colorSteps = 4.0;
    luma = floor(luma * colorSteps) / colorSteps;

    // Create retro color scheme with audio reactivity (like Atari color palette)
    float3 retroColor;
    if (luma < 0.25) {
        // Dark - deep purple/black (Atari dark colors)
        retroColor = float3(0.05, 0.0, 0.15) + float3(uniforms.bassLevel * 0.2, 0.0, uniforms.bassLevel * 0.1);
    } else if (luma < 0.5) {
        // Mid-dark - cyan/blue (classic computer blue)
        retroColor = float3(0.0, 0.4, 0.7) + float3(0.0, uniforms.midLevel * 0.3, uniforms.bassLevel * 0.2);
    } else if (luma < 0.75) {
        // Mid-bright - magenta/pink (Atari signature colors)
        retroColor = float3(0.9, 0.3, 0.7) + float3(uniforms.trebleLevel * 0.2, 0.0, uniforms.midLevel * 0.15);
    } else {
        // Bright - white/yellow (phosphor glow)
        retroColor = float3(1.0, 0.95, 0.7) + float3(0.0, uniforms.trebleLevel * 0.15, 0.0);
    }

    // === RETRO GEOMETRIC PATTERNS (Propeller chip style) ===
    // Simple geometric shapes like early computer graphics

    // Moving grid pattern (like raster graphics)
    float2 gridUV = pixelUV * 8.0;
    float gridX = step(0.7, fmod(gridUV.x + time * 1.5, 1.0));
    float gridY = step(0.7, fmod(gridUV.y + time * 1.2, 1.0));
    float grid = max(gridX, gridY);

    // Diagonal stripes (classic Atari pattern)
    float stripes = step(0.5, fmod((pixelUV.x + pixelUV.y) * 6.0 + time * 2.0, 1.0));

    // Circular patterns (fake 3D tunnel effect - very 70s)
    float2 center = float2(0.5, 0.5);
    float2 centeredUV = pixelUV - center;
    float radius = length(centeredUV);
    float tunnel = fmod(radius * 12.0 - time * 6.0, 1.0);
    tunnel = step(0.4, tunnel) * step(tunnel, 0.6);

    // Concentric squares (like early vector graphics)
    float2 squareUV = abs(centeredUV);
    float squareDist = max(squareUV.x, squareUV.y);
    float squares = fmod(squareDist * 16.0 - time * 4.0, 1.0);
    squares = step(0.3, squares) * step(squares, 0.5);

    // === AUDIO-REACTIVE EFFECTS ===
    // Bass creates pulsing circles (like oscilloscope display)
    float bassRadius = 0.1 + uniforms.bassLevel * 0.25;
    float bassPulse = smoothstep(bassRadius - 0.05, bassRadius, radius) *
                      smoothstep(bassRadius + 0.1, bassRadius + 0.05, radius);

    // Mids create horizontal bars (like frequency display)
    float midBars = step(0.8, fmod(pixelUV.y * 12.0 + time * uniforms.midLevel * 8.0, 1.0));

    // Treble creates sparkles/stars (like digital noise)
    float sparkles = 0.0;
    for(int i = 0; i < 4; i++) {
        float2 sparklePos = float2(fmod(float(i) * 0.37 + time * 0.08, 1.0),
                                   fmod(float(i) * 0.53 + time * 0.12, 1.0));
        float sparkleSize = uniforms.trebleLevel * 0.04 + 0.01;
        float dist = length(pixelUV - sparklePos);
        sparkles += smoothstep(sparkleSize, 0.0, dist);
    }

    // === COMBINE RETRO EFFECTS ===
    float pattern = 0.0;

    // Select pattern based on audio levels (like switching video modes)
    if (uniforms.bassLevel > 0.4) {
        // Bass mode - tunnel and pulse effects
        pattern = tunnel + bassPulse * 2.0;
    } else if (uniforms.midLevel > 0.4) {
        // Mid mode - stripes and bars
        pattern = stripes + midBars;
    } else if (uniforms.trebleLevel > 0.4) {
        // Treble mode - grid and sparkles
        pattern = grid + sparkles * 2.0;
    } else {
        // Default mode - geometric patterns
        pattern = squares * 0.5 + grid * 0.3;
    }

    pattern = saturate(pattern);

    // === RETRO CRT SCANLINES ===
    // Simulate composite video scanlines
    float scanlineFreq = 150.0; // Adjusted for realistic scanlines
    float scanlines = sin(pixelUV.y * 3.14159 * scanlineFreq) * 0.08 + 0.92;

    // === RETRO COLOR BLEEDING ===
    // Simulate composite video color bleeding
    float colorBleed = sin(pixelUV.x * 3.14159 * 60.0) * 0.05;
    retroColor.r += colorBleed;
    retroColor.b -= colorBleed * 0.5;

    // === FINAL RETRO COMPOSITION ===
    // Mix base color with patterns
    float3 finalColor = mix(retroColor * 0.6, retroColor * 1.4, pattern);

    // Apply scanlines
    finalColor *= scanlines;

    // Add retro phosphor glow effect
    finalColor += pow(pattern, 4.0) * float3(0.2, 0.3, 0.1);

    // Vintage color grading (like old CRT phosphors)
    finalColor.r *= 1.05; // Slight red boost
    finalColor.g *= 0.95; // Slight green reduction
    finalColor.b *= 1.15; // Blue boost for CRT look

    // Audio-reactive brightness with vintage fade
    float brightness = 0.7 + audioReactivity * 0.3;
    finalColor *= brightness;

    // Vintage contrast curve
    finalColor = pow(finalColor, float3(1.1));

    // Add subtle noise like analog video
    float noise = fmod(sin(dot(pixelUV, float2(12.9898, 78.233))) * 43758.5453, 1.0);
    finalColor += (noise - 0.5) * 0.02;

    finalColor = saturate(finalColor);

    float4 outputColor = float4(finalColor, inputColor.a);
    outputTexture.write(outputColor, gid);
}

// MARK: - Op-Art Triangles Effect (Premium)
kernel void opArtTrianglesEffect(texture2d<float, access::read> inputTexture [[texture(0)]],
                                texture2d<float, access::write> outputTexture [[texture(1)]],
                                constant DiscoUniforms &uniforms [[buffer(0)]],
                                uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }

    float4 inputColor = inputTexture.read(gid);

    // Audio reactivity factor
    float audioReactivity = (uniforms.bassLevel + uniforms.midLevel + uniforms.trebleLevel) / 3.0;
    float time = uniforms.time;

    // === OPTICAL PSYCH OUT EFFECT (FROM QUARTZ COMPOSER) ===
    // Based on "Optical psych out.qtz" psychedelic shader

    // Convert to normalized device coordinates (matching original shader)
    float2 uv_psych = (2.0 * float2(gid) - float2(outputTexture.get_width(), outputTexture.get_height())) / float(outputTexture.get_height());

    // Rotation matrix function (from original shader)
    float rotation_angle = time * 0.25 + audioReactivity * 0.5; // Audio affects rotation speed
    float c = cos(rotation_angle);
    float s = sin(rotation_angle);
    float2x2 rotationMatrix = float2x2(c, -s, s, c);

    // Apply rotation and take absolute value
    uv_psych = abs(uv_psych * rotationMatrix);

    // Polar coordinate transformation (from original shader)
    float2 polar = float2(atan2(uv_psych.x, uv_psych.y), length(uv_psych));

    // Initialize color
    float3 psychColor = float3(0.0);

    // Audio-reactive frequency multipliers
    float freq1 = 8.0 + uniforms.bassLevel * 12.0;        // Bass affects first pattern: 8-20
    float freq2 = 14.0 + uniforms.trebleLevel * 20.0;     // Treble affects second pattern: 14-34
    float freq3 = 58.0 + uniforms.midLevel * 40.0;        // Mid affects third pattern: 58-98

    // Multi-color psychedelic patterns - each frequency band gets its own color

    // Pattern 1: Purple/Magenta (bass reactive)
    float pattern1 = sin(freq1 * tan(polar.y * 2.0 - time) + time) + (freq1 * polar.x - freq1 * polar.y);
    float3 purple = float3(0.8, 0.2, 0.9);
    psychColor = mix(psychColor, purple, pattern1);

    // Pattern 2: Orange/Red (treble reactive)
    float pattern2 = cos(freq1 * sin(polar.y * freq2 + time * 1.0) + freq3 * polar.x) * (freq1 * polar.y - 99918.0 * polar.x);
    float3 orange = float3(1.0, 0.3, 0.0);
    psychColor = mix(psychColor, orange, pattern2);

    // Pattern 3: Cyan/Blue (mid reactive)
    float pattern3 = sin(freq2 * cos(polar.x * 3.0 + time * 2.0) + polar.y * freq1);
    float3 cyan = float3(0.0, 0.9, 0.8);
    psychColor = mix(psychColor, cyan, pattern3);

    // Pattern 4: Yellow/Green (bass + treble combo)
    float pattern4 = cos(freq3 * sin(polar.y * 6.0 - time * 0.5) + polar.x * freq2 * 0.3);
    float3 yellow = float3(0.9, 0.9, 0.1);
    psychColor = mix(psychColor, yellow, pattern4);

    // Pattern 5: Hot Pink (all frequencies)
    float pattern5 = sin(freq1 * 0.5 + freq2 * 0.3) * cos(polar.y * freq3 * 0.1 + time);
    float3 hotpink = float3(1.0, 0.1, 0.6);
    psychColor = mix(psychColor, hotpink, pattern5);

    // Audio-reactive enhancements
    // Modulate patterns with audio using same frequency variables
    float bass_mod = sin(freq1 * tan(polar.y * 2.0 - time + uniforms.bassLevel * 5.0) + time);
    float treble_mod = cos(freq1 * sin(polar.y * freq2 + time + uniforms.trebleLevel * 10.0));

    // Additional audio-reactive color layers
    float3 audio_purple = float3(0.6 + uniforms.bassLevel * 0.4, 0.1, 0.9);
    float3 audio_orange = float3(0.9, 0.3 + uniforms.midLevel * 0.5, uniforms.trebleLevel * 0.3);

    psychColor = mix(psychColor, audio_purple, bass_mod * uniforms.bassLevel);
    psychColor = mix(psychColor, audio_orange, treble_mod * uniforms.trebleLevel);

    // Sample original video content for blending
    float3 videoColor = inputTexture.read(gid).rgb;

    // Use pattern brightness as alpha mask - white parts become transparent
    float pattern_brightness = dot(psychColor, float3(0.299, 0.587, 0.114)); // Luminance
    float pattern_alpha = 1.0 - smoothstep(0.3, 0.8, pattern_brightness); // White areas = low alpha

    // Audio affects pattern visibility
    pattern_alpha *= (0.7 + audioReactivity * 0.3);

    // Blend using alpha mask - white parts show video, dark parts show pattern
    psychColor = mix(videoColor, psychColor, pattern_alpha);

    // Audio-reactive intensity modulation
    float intensity = 1.0 + sin(time * 3.0) * audioReactivity * 0.3;
    psychColor *= intensity;

    float4 outputColor = float4(psychColor, inputColor.a);
    outputTexture.write(outputColor, gid);
}

// HSV to RGB conversion function
float3 hsv_to_rgb(float h, float s, float v) {
    float3 rgb = mix(float3(1.0), clamp((abs(fract(h + float3(3.0, 2.0, 1.0) / 3.0) * 6.0 - 3.0) - 1.0), 0.0, 1.0), s) * v;
    return rgb;
}

// MARK: - Op-Art Waves Effect (from OpArtSeries1-8.qtz)
kernel void gridRoomEffect(texture2d<float, access::read> inputTexture [[texture(0)]],
                          texture2d<float, access::write> outputTexture [[texture(1)]],
                          constant DiscoUniforms &uniforms [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }

    float4 inputColor = inputTexture.read(gid);
    float2 resolution = float2(outputTexture.get_width(), outputTexture.get_height());
    float time = uniforms.time;

    // Audio reactivity
    float audioReactivity = (uniforms.bassLevel + uniforms.midLevel + uniforms.trebleLevel) / 3.0;

    // === OP-ART WAVES EFFECT (FROM OpArtSeries1-8.QTZ) ===
    // Convert to normalized device coordinates (-1 to 1)
    float2 uv = 2.0 * float2(gid) / resolution - 1.0;

    // Edge detection for pattern guidance (will be calculated later)
    float edge_strength = 0.0;
    float2 edge_direction = float2(0.0);

    // Audio-reactive parameters enhanced with edge-following
    float A = uniforms.bassLevel * 10.0 + time * 0.5;        // Bass affects wave phase
    float B = uniforms.trebleLevel * 10.0 + time * 0.3;      // Treble affects vertical wave
    float C = uniforms.midLevel * 10.0 + time * 0.4;         // Mid affects horizontal distortion
    float D = audioReactivity * 15.0 + time * 0.6;           // Overall audio affects final distortion

    // Original shader transformations with audio enhancement
    uv *= (1.0 - length(uv * (1.0 + audioReactivity * 0.3))); // Audio affects lens distortion
    float wave_value = cos(uv.x * (6.0 + uniforms.bassLevel * 4.0) + A) + sin(time + uv.y * (6.0 + uniforms.trebleLevel * 4.0) + B);
    uv *= sin(abs(wave_value));
    uv += cos(uv.x * (16.0 + uniforms.midLevel * 8.0) + C) * sin(time + uv.y * (16.0 + audioReactivity * 8.0) + D);

    // Calculate distance for color effect with edge enhancement
    float r = length(uv);

    // Original color calculation with audio and edge enhancements
    float3 base_color = float3(1.0) - float3(exp(r) - 1.1);

    // Edge-enhanced HSV color cycling with enhanced complexity
    float edge_hue_shift = edge_strength * sin(time * 2.0 + dot(edge_direction, uv) * 5.0) * 2.0;
    float hue = 0.0 + r * (8.0 + uniforms.bassLevel * 4.0 + edge_strength * 3.0) +
                time * 0.4 + audioReactivity * 4.0 + edge_hue_shift;
    float saturation = 1.0;
    float brightness = 1.0 + sin(time * 2.0 + r * 8.0) * audioReactivity * 0.3;

    float3 hsv_color = hsv_to_rgb(hue, saturation, brightness);

    // Combine base color with HSV color
    float3 pattern_color = base_color * hsv_color;

    // Audio-reactive intensity and pulsing - smoother pulsing
    float intensity = 1.0 + sin(time * 2.0) * audioReactivity * 0.3;
    pattern_color *= intensity;

    // Pattern strength for blending - smoother transitions
    float pattern_strength = 0.85 + audioReactivity * 0.3 + smoothstep(0.0, 1.0, edge_strength) * 0.2;

    // === ENHANCED AUDIO-REACTIVE CHROMATIC ABERRATIONS ===
    // Multi-layered aberration with different frequency responses
    float base_aberration = audioReactivity * uniforms.chromaticAberration * 25.0;

    // Bass creates large horizontal shifts (like vinyl warping) - smoother motion
    float2 bass_offset = float2(
        sin(time * 1.2 + uniforms.bassLevel * 6.0) * uniforms.bassLevel * 0.08,
        cos(time * 0.8 + uniforms.bassLevel * 4.0) * uniforms.bassLevel * 0.04
    );

    // Mids create circular/orbital motion - gentler rotation
    float mid_angle = time * 2.5 + uniforms.midLevel * 8.0;
    float2 mid_offset = float2(
        cos(mid_angle) * uniforms.midLevel * 0.06,
        sin(mid_angle) * uniforms.midLevel * 0.06
    );

    // Treble creates subtle shimmer movements - much smoother
    float2 treble_offset = float2(
        sin(time * 6.0 + r * 8.0) * uniforms.trebleLevel * 0.04,
        cos(time * 7.0 + r * 10.0) * uniforms.trebleLevel * 0.03
    );

    // Different offsets for each color channel with frequency-specific movement
    float2 red_offset = bass_offset * 1.2 + float2(base_aberration * 0.8, 0.0);
    float2 green_offset = mid_offset * 1.0 + float2(0.0, base_aberration * 0.6);
    float2 blue_offset = treble_offset * 1.5 + float2(-base_aberration * 0.7, base_aberration * 0.9);

    // Add spiral distortion based on audio
    float spiral_factor = audioReactivity * 2.0;
    float spiral_angle = atan2(uv.y, uv.x) + r * spiral_factor + time * audioReactivity;
    float spiral_radius = length(uv);
    float2 spiral_offset = float2(cos(spiral_angle), sin(spiral_angle)) * r * audioReactivity * 0.1;

    red_offset += spiral_offset * 0.8;
    green_offset += spiral_offset * 0.5;
    blue_offset += spiral_offset * 1.2;

    // Apply offsets to the UV coordinates and recalculate pattern for each channel
    float2 uv_red = uv + red_offset;
    float2 uv_green = uv + green_offset;
    float2 uv_blue = uv + blue_offset;

    // Recalculate wave transformations for each aberrated channel
    // Red channel (bass-driven)
    uv_red *= (1.0 - length(uv_red * (1.0 + uniforms.bassLevel * 0.5)));
    float wave_red = cos(uv_red.x * (6.0 + uniforms.bassLevel * 6.0) + A) + sin(time + uv_red.y * (6.0 + uniforms.bassLevel * 4.0) + B);
    uv_red *= sin(abs(wave_red));
    uv_red += cos(uv_red.x * (16.0 + uniforms.bassLevel * 12.0) + C) * sin(time + uv_red.y * (16.0 + uniforms.bassLevel * 8.0) + D);

    // Green channel (mid-driven)
    uv_green *= (1.0 - length(uv_green * (1.0 + uniforms.midLevel * 0.4)));
    float wave_green = cos(uv_green.x * (6.0 + uniforms.midLevel * 5.0) + A * 1.1) + sin(time * 1.1 + uv_green.y * (6.0 + uniforms.midLevel * 4.0) + B * 1.1);
    uv_green *= sin(abs(wave_green));
    uv_green += cos(uv_green.x * (16.0 + uniforms.midLevel * 10.0) + C * 1.1) * sin(time * 1.1 + uv_green.y * (16.0 + uniforms.midLevel * 8.0) + D * 1.1);

    // Blue channel (treble-driven)
    uv_blue *= (1.0 - length(uv_blue * (1.0 + uniforms.trebleLevel * 0.6)));
    float wave_blue = cos(uv_blue.x * (6.0 + uniforms.trebleLevel * 7.0) + A * 0.9) + sin(time * 0.9 + uv_blue.y * (6.0 + uniforms.trebleLevel * 5.0) + B * 0.9);
    uv_blue *= sin(abs(wave_blue));
    uv_blue += cos(uv_blue.x * (16.0 + uniforms.trebleLevel * 14.0) + C * 0.9) * sin(time * 0.9 + uv_blue.y * (16.0 + uniforms.trebleLevel * 10.0) + D * 0.9);

    // Calculate separate distances for each aberrated channel
    float r_red = length(uv_red);
    float r_green = length(uv_green);
    float r_blue = length(uv_blue);

    // Generate aberrated pattern colors with enhanced frequency-specific variations
    float3 base_red = float3(1.0) - float3(exp(r_red) - 1.1);
    float3 base_green = float3(1.0) - float3(exp(r_green) - 1.1);
    float3 base_blue = float3(1.0) - float3(exp(r_blue) - 1.1);

    // Enhanced audio-reactive HSV for each channel with expanded hue range - smoother transitions
    float hue_red = 0.0 + r_red * (6.0 + uniforms.bassLevel * 8.0) + time * 0.5 + sin(uniforms.bassLevel * 8.0 + time * 2.0) * 0.4;
    float hue_green = 0.33 + r_green * (7.0 + uniforms.midLevel * 6.0) + time * 0.4 + cos(uniforms.midLevel * 6.0 + time * 1.5) * 0.35;
    float hue_blue = 0.66 + r_blue * (8.0 + uniforms.trebleLevel * 7.0) + time * 0.3 + sin(uniforms.trebleLevel * 10.0 + time * 1.8) * 0.45;

    // Enhanced saturation and brightness modulation
    float sat_red = 1.0 + sin(time * 3.0 + r_red * 8.0) * uniforms.bassLevel * 0.3;
    float sat_green = 1.0 + cos(time * 4.0 + r_green * 6.0) * uniforms.midLevel * 0.25;
    float sat_blue = 1.0 + sin(time * 5.0 + r_blue * 10.0) * uniforms.trebleLevel * 0.4;

    float bright_red = brightness * (1.0 + uniforms.bassLevel * 0.4);
    float bright_green = brightness * (1.0 + uniforms.midLevel * 0.3);
    float bright_blue = brightness * (1.0 + uniforms.trebleLevel * 0.5);

    float3 hsv_red = hsv_to_rgb(hue_red, sat_red, bright_red);
    float3 hsv_green = hsv_to_rgb(hue_green, sat_green, bright_green);
    float3 hsv_blue = hsv_to_rgb(hue_blue, sat_blue, bright_blue);

    // Combine aberrated channels with enhanced blending
    float3 aberrated_pattern;
    aberrated_pattern.r = (base_red * hsv_red).r;
    aberrated_pattern.g = (base_green * hsv_green).g;
    aberrated_pattern.b = (base_blue * hsv_blue).b;

    // Add cross-channel color bleeding for more psychedelic effect
    float bleed_factor = audioReactivity * 0.3;
    aberrated_pattern.r += (base_green * hsv_green).r * bleed_factor * uniforms.bassLevel;
    aberrated_pattern.g += (base_blue * hsv_blue).g * bleed_factor * uniforms.midLevel;
    aberrated_pattern.b += (base_red * hsv_red).b * bleed_factor * uniforms.trebleLevel;

    // Enhanced mixing with more dramatic audio response - increased strength
    float aberration_mix = min(audioReactivity * 2.5, 1.0);
    pattern_color = mix(pattern_color, aberrated_pattern, aberration_mix);

    // Apply intensity after aberrations
    pattern_color *= intensity;

    // === EDGE DETECTION FOR WAVE GUIDANCE ===
    // Sample neighboring pixels for edge detection
    uint2 gid_up = uint2(gid.x, max(0, int(gid.y) - 1));
    uint2 gid_down = uint2(gid.x, min(int(resolution.y) - 1, int(gid.y) + 1));
    uint2 gid_left = uint2(max(0, int(gid.x) - 1), gid.y);
    uint2 gid_right = uint2(min(int(resolution.x) - 1, int(gid.x) + 1), gid.y);

    // Sample neighboring colors
    float3 color_up = inputTexture.read(gid_up).rgb;
    float3 color_down = inputTexture.read(gid_down).rgb;
    float3 color_left = inputTexture.read(gid_left).rgb;
    float3 color_right = inputTexture.read(gid_right).rgb;

    // Sobel edge detection
    float3 grad_x = (color_right - color_left) * 0.5;
    float3 grad_y = (color_down - color_up) * 0.5;

    // Update edge strength and direction for pattern guidance
    edge_strength = length(grad_x) + length(grad_y);
    edge_direction = normalize(float2(dot(grad_x, float3(0.299, 0.587, 0.114)),
                                    dot(grad_y, float3(0.299, 0.587, 0.114))));

    // Smooth edge strength to avoid harsh transitions - more gradual
    edge_strength = smoothstep(0.05, 0.8, edge_strength);

    // Temporal smoothing of edge strength to reduce flicker
    edge_strength = mix(edge_strength, sin(time * 1.5) * 0.1 + 0.9, 0.1);

    // === EDGE-GUIDED OP-ART PATTERN MODULATION ===
    // Modify Op-Art parameters based on detected edges
    A += edge_strength * dot(edge_direction, float2(1.0, 0.0)) * 8.0; // Horizontal edges affect A
    B += edge_strength * dot(edge_direction, float2(0.0, 1.0)) * 6.0; // Vertical edges affect B
    C += edge_strength * length(edge_direction) * 5.0;                // Overall edge strength affects C
    D += edge_strength * sin(time + dot(edge_direction, uv)) * 10.0;   // Dynamic edge following

    // === MULTI-LAYERED OP-ART PATTERN GENERATION ===
    // Layer 1: Original OpArt waves with edge enhancement
    uv *= (1.0 - length(uv * (1.0 + audioReactivity * 0.3 + edge_strength * 0.2)));
    float wave_layer1 = cos(uv.x * (6.0 + uniforms.bassLevel * 4.0 + edge_strength * 3.0) + A) +
                        sin(time + uv.y * (6.0 + uniforms.trebleLevel * 4.0 + edge_strength * 2.0) + B);

    // Layer 2: Interference patterns
    float wave_layer2 = sin(uv.x * (12.0 + uniforms.midLevel * 6.0) + A * 1.3 + time * 1.5) *
                        cos(uv.y * (8.0 + uniforms.bassLevel * 3.0) + B * 0.8 + time * 0.7);

    // Layer 3: Frequency modulation waves - smoother frequency changes
    float freq_mod = 3.0 + sin(time * 0.3) * 1.5 + audioReactivity * 3.0;
    float wave_layer3 = cos(uv.x * freq_mod + sin(uv.y * freq_mod * 1.1) + A * 0.6) +
                        sin(uv.y * freq_mod * 0.9 + cos(uv.x * freq_mod * 1.05) + B * 1.2);

    // Layer 4: Spiral patterns - gentler spiral motion
    float wave_layer4 = sin(spiral_angle * (6.0 + uniforms.trebleLevel * 4.0) +
                           spiral_radius * (15.0 + uniforms.bassLevel * 6.0) + C);

    // Layer 5: Moiré interference patterns - reduced frequency jumps
    float moire_freq1 = 12.0 + uniforms.bassLevel * 5.0;
    float moire_freq2 = 13.0 + uniforms.trebleLevel * 6.0;
    float wave_layer5 = (sin(uv.x * moire_freq1 + time * 1.2) * sin(uv.y * moire_freq1 + A)) +
                        (cos(uv.x * moire_freq2 + time * 0.8) * cos(uv.y * moire_freq2 + B));

    // Combine all wave layers with edge-enhanced weights
    float combined_waves = (wave_layer1 * (1.0 + edge_strength * 0.5)) +
                          (wave_layer2 * 0.6) +
                          (wave_layer3 * 0.4) +
                          (wave_layer4 * 0.7) +
                          (wave_layer5 * 0.3);

    // Apply combined wave transformations
    uv *= sin(abs(combined_waves));

    // Second transformation pass with more complex patterns
    float secondary_transform = cos(uv.x * (16.0 + uniforms.midLevel * 8.0 + edge_strength * 4.0) + C) *
                               sin(time + uv.y * (16.0 + audioReactivity * 8.0 + edge_strength * 6.0) + D);

    // Add ripple effects
    float ripple_phase = time * 3.0 + combined_waves * 2.0;
    float ripples = sin(length(uv) * (25.0 + uniforms.bassLevel * 15.0) + ripple_phase) * 0.1;

    uv += secondary_transform + ripples;

    // === ORGANIC WAVE DISTORTION ===
    // Organic flowing waves - much slower and smoother with separate x/y randomization
    float2 wave_distortion = float2(0.0);

    // Generate separate pseudo-random offsets for x and y components
    float randX1 = fract(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
    float randX2 = fract(sin(dot(uv, float2(34.567, 91.827))) * 23421.6789);
    float randX3 = fract(sin(dot(uv, float2(56.789, 45.678))) * 87654.3210);

    float randY1 = fract(sin(dot(uv, float2(98.765, 23.456))) * 65432.1098);
    float randY2 = fract(sin(dot(uv, float2(67.890, 34.567))) * 54321.9876);
    float randY3 = fract(sin(dot(uv, float2(45.123, 78.901))) * 98765.4321);

    // X-component waves with separate randomization
    wave_distortion.x += sin(uv.y * 1.5 + time * 0.8 + randX1 * 6.28) * uniforms.bassLevel * 0.08;
    wave_distortion.x += cos(uv.y * 0.9 + time * 0.5 + randX2 * 6.28) * uniforms.bassLevel * 0.05;
    wave_distortion.x += sin(uv.x * 0.6 + time * 0.3 + randX3 * 6.28) * uniforms.midLevel * 0.03;

    // Y-component waves with separate randomization
    wave_distortion.y += sin(uv.x * 1.2 + time * 0.6 + randY1 * 6.28) * uniforms.trebleLevel * 0.06;
    wave_distortion.y += cos(uv.x * 0.7 + time * 0.35 + randY2 * 6.28) * uniforms.trebleLevel * 0.04;
    wave_distortion.y += sin(uv.y * 0.5 + time * 0.25 + randY3 * 6.28) * uniforms.midLevel * 0.03;

    // Add very slow organic drift phases with separate x/y randomization
    float organic_phaseX = sin(time * 0.15 + randX1 * 3.14) * 0.8;
    float organic_phaseY = cos(time * 0.22 + randY1 * 3.14) * 0.6;

    // Apply organic phases to create flowing motion
    wave_distortion.x += sin(organic_phaseX + randX2 * 2.0) * uniforms.audioLevel * 0.02;
    wave_distortion.y += cos(organic_phaseY + randY2 * 2.0) * uniforms.audioLevel * 0.02;

    // Add much more dramatic trailing effect
    float2 center = float2(0.5, 0.5);
    float distance_from_center = length(uv - center);

    // Create more visible trailing effects
    float trail_fade = exp(-distance_from_center * 4.0); // Stronger distance fade
    float time_trail = sin(time * 0.3 + distance_from_center * 5.0) * 0.7 + 0.3; // More dramatic time trailing

    // Audio creates strong ripples that trail off quickly
    float audio_ripple = 1.0 - smoothstep(0.0, 0.5, distance_from_center - uniforms.audioLevel * 0.8);

    // Combine trailing effects with much more contrast
    float total_trail = trail_fade * time_trail * (0.3 + audio_ripple * 0.7);
    total_trail = clamp(total_trail, 0.0, 1.0); // Allow complete fade-out

    // Apply stronger trailing to wave distortion
    wave_distortion *= total_trail;

    // Apply wave distortion to video sampling
    float2 distorted_coords = (float2(gid) + wave_distortion * resolution * 0.1) / resolution;
    distorted_coords = clamp(distorted_coords, float2(0.0), float2(1.0));
    uint2 sample_gid = uint2(distorted_coords * resolution);
    sample_gid = clamp(sample_gid, uint2(0), uint2(resolution) - 1);

    float3 distortedVideoColor = inputTexture.read(sample_gid).rgb;

    // Use alpha masking based on pattern brightness to show video through
    float pattern_brightness = dot(pattern_color, float3(0.299, 0.587, 0.114));
    float pattern_alpha = smoothstep(0.2, 0.8, pattern_brightness) * pattern_strength;

    float3 finalColor = mix(distortedVideoColor, pattern_color, pattern_alpha);

    // VERY OBVIOUS TRAILING EFFECT for VHS
    // Create bright rainbow trails that follow wave movement
    if (uniforms.audioLevel > 0.01) {
        // Create multiple colored trails in different directions
        for (int i = 1; i <= 12; i++) {
            float trail_factor = float(i);

            // Create trails in multiple directions based on wave movement
            int trail_x = int(gid.x) - i * 3; // Horizontal trails
            int trail_y = int(gid.y) - i * 2; // Diagonal trails

            // Horizontal rainbow trails
            if (trail_x >= 0) {
                uint2 trail_pos = uint2(trail_x, gid.y);
                float3 trail_color = inputTexture.read(trail_pos).rgb;

                float trail_strength = (1.0 - trail_factor / 12.0) * uniforms.audioLevel * 2.0;

                // Make rainbow trails - cycle through colors
                float hue_shift = trail_factor * 0.5;
                trail_color.r += sin(hue_shift) * trail_strength * 0.8;
                trail_color.g += sin(hue_shift + 2.0) * trail_strength * 0.8;
                trail_color.b += sin(hue_shift + 4.0) * trail_strength * 0.8;

                finalColor = mix(finalColor, trail_color, trail_strength * 0.4);
            }

            // Vertical trails
            if (trail_y >= 0) {
                uint2 trail_pos = uint2(gid.x, trail_y);
                float3 trail_color = inputTexture.read(trail_pos).rgb;

                float trail_strength = (1.0 - trail_factor / 12.0) * uniforms.audioLevel * 1.5;

                // Blue-purple trails for vertical
                trail_color.b += trail_strength * 1.0;
                trail_color.r += trail_strength * 0.5;

                finalColor = mix(finalColor, trail_color, trail_strength * 0.3);
            }
        }

        // Add overall brightness boost when trailing
        finalColor *= (1.0 + uniforms.audioLevel * 0.5);
    }

    float4 outputColor = float4(finalColor, inputColor.a);
    outputTexture.write(outputColor, gid);
}

// MARK: - Psychedelic Waves Effect (Combined VHS + OP-ART)
kernel void psychedelicWavesEffect(texture2d<float, access::read> inputTexture [[texture(0)]],
                                  texture2d<float, access::write> outputTexture [[texture(1)]],
                                  constant DiscoUniforms &uniforms [[buffer(0)]],
                                  uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }

    float2 resolution = float2(outputTexture.get_width(), outputTexture.get_height());
    float2 uv = float2(gid) / resolution;
    float4 inputColor = inputTexture.read(gid);
    float time = uniforms.time;

    // Audio reactivity from both bass and overall levels
    float audioReactivity = (uniforms.bassLevel + uniforms.midLevel + uniforms.trebleLevel) / 3.0;

    // === OP-ART WAVES FOUNDATION ===
    // Convert to centered coordinates (-1 to 1)
    float2 centeredUV = 2.0 * uv - 1.0;

    // Audio-reactive wave parameters
    float A = uniforms.bassLevel * 10.0 + time * 0.5;
    float B = uniforms.trebleLevel * 10.0 + time * 0.3;
    float C = uniforms.midLevel * 10.0 + time * 0.4;
    float D = audioReactivity * 15.0 + time * 0.6;

    // Generate organic randomized wave patterns
    float randX1 = fract(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
    float randY1 = fract(sin(dot(uv, float2(98.765, 23.456))) * 65432.1098);

    // Organic wave transformations
    centeredUV *= (1.0 - length(centeredUV * (1.0 + uniforms.bassLevel * 0.5)));
    float wave1 = cos(centeredUV.x * (6.0 + uniforms.bassLevel * 6.0) + A + randX1 * 6.28) +
                  sin(time + centeredUV.y * (6.0 + uniforms.bassLevel * 4.0) + B + randY1 * 6.28);
    centeredUV *= sin(abs(wave1));
    centeredUV += cos(centeredUV.x * (16.0 + uniforms.bassLevel * 12.0) + C) *
                  sin(time + centeredUV.y * (16.0 + uniforms.bassLevel * 8.0) + D);

    // Distance for circular patterns
    float r = length(centeredUV);

    // Generate psychedelic pattern
    float3 base_pattern = float3(1.0) - float3(exp(r) - 1.1);

    // Enhanced HSV color cycling with audio reactivity
    float hue = 0.0 + r * (6.0 + uniforms.bassLevel * 8.0) + time * 0.5;
    float saturation = 1.0 + sin(time * 3.0 + r * 8.0) * uniforms.bassLevel * 0.3;
    float brightness = 1.0 + uniforms.audioLevel * 0.4;

    float3 hsv_color = hsv_to_rgb(hue, saturation, brightness);
    float3 pattern_color = base_pattern * hsv_color * uniforms.intensity;

    // === VHS DISTORTION LAYER ===
    // Apply VHS-style wave distortion
    float2 wave_distortion = float2(0.0);

    // Organic horizontal waves
    wave_distortion.x += sin(uv.y * 1.5 + time * 0.8 + randX1 * 6.28) * uniforms.bassLevel * 0.08;
    wave_distortion.y += sin(uv.x * 1.2 + time * 0.6 + randY1 * 6.28) * uniforms.trebleLevel * 0.06;

    // Apply wave distortion to sampling
    float2 distorted_coords = (float2(gid) + wave_distortion * resolution * 0.1) / resolution;
    distorted_coords = clamp(distorted_coords, float2(0.0), float2(1.0));
    uint2 sample_gid = uint2(distorted_coords * resolution);
    sample_gid = clamp(sample_gid, uint2(0), uint2(resolution) - 1);

    float3 distorted_video = inputTexture.read(sample_gid).rgb;

    // === PSYCHEDELIC TRAILING EFFECT ===
    float3 final_color = mix(distorted_video, pattern_color, 0.6);

    if (uniforms.audioLevel > 0.01) {
        // Create flowing rainbow trails
        for (int i = 1; i <= 10; i++) {
            float trail_factor = float(i);
            int trail_x = int(gid.x) - i * 3;
            int trail_y = int(gid.y) - i * 2;

            if (trail_x >= 0) {
                uint2 trail_pos = uint2(trail_x, gid.y);
                float3 trail_color = inputTexture.read(trail_pos).rgb;

                float trail_strength = (1.0 - trail_factor / 10.0) * uniforms.audioLevel * 1.5;
                float hue_shift = trail_factor * 0.6 + time * 2.0;

                trail_color.r += sin(hue_shift) * trail_strength * 0.8;
                trail_color.g += sin(hue_shift + 2.0) * trail_strength * 0.8;
                trail_color.b += sin(hue_shift + 4.0) * trail_strength * 0.8;

                final_color = mix(final_color, trail_color, trail_strength * 0.3);
            }
        }

        final_color *= (1.0 + uniforms.audioLevel * 0.3);
    }

    float4 outputColor = float4(final_color, inputColor.a);
    outputTexture.write(outputColor, gid);
}

// MARK: - Basic Feedback Effect (Premium)
kernel void basicFeedbackEffect(texture2d<float, access::read> inputTexture [[texture(0)]],
                                texture2d<float, access::write> outputTexture [[texture(1)]],
                                texture2d<float, access::read> feedbackTexture [[texture(2)]],
                                constant DiscoUniforms &uniforms [[buffer(0)]],
                                uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }

    float2 resolution = float2(outputTexture.get_width(), outputTexture.get_height());
    float2 uv = float2(gid) / resolution;

    // Sample current frame
    float4 currentFrame = inputTexture.read(gid);

    // === BASIC FEEDBACK IMPLEMENTATION ===
    // Scale down slightly to create inward drift effect
    float feedback_scale = 0.998 - uniforms.audioLevel * 0.002; // Audio affects feedback scale
    float2 feedback_uv = uv * feedback_scale;

    // Convert to texture coordinates with bounds checking
    uint2 feedback_coord = uint2(clamp(feedback_uv * resolution, float2(0.0), resolution - 1.0));

    // Sample feedback buffer (previous frame)
    float4 feedbackFrame = feedbackTexture.read(feedback_coord);

    // Audio-reactive feedback mixing
    float feedback_strength = 0.99 + sin(uniforms.time * 3.0) * uniforms.audioLevel * 0.02;
    float3 mixed_color = mix(currentFrame.rgb, feedbackFrame.rgb, feedback_strength);

    // Write result
    float4 outputColor = float4(mixed_color, currentFrame.a);
    outputTexture.write(outputColor, gid);
}

// ================================
// LFO MODULATION EFFECT (CMYK OSCILLATOR)
// ================================

kernel void lfoModulationEffect(texture2d<float, access::read> inputTexture [[texture(0)]],
                               texture2d<float, access::write> outputTexture [[texture(1)]],
                               constant DiscoUniforms& uniforms [[buffer(0)]],
                               uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }

    float2 uv = float2(gid) / float2(inputTexture.get_width(), inputTexture.get_height());
    float2 centeredUV = uv * 2.0 - 1.0;

    // Audio reactivity components
    float totalAudio = uniforms.audioLevel;
    float bassReactivity = uniforms.bassLevel;
    float midReactivity = uniforms.midLevel;
    float trebleReactivity = uniforms.trebleLevel;
    float time = uniforms.time;

    // === LFO OSCILLATORS ===
    // Create multiple LFO waves with different frequencies and phases

    // Primary LFO - Bass synchronized (0.5-2 Hz)
    float lfo1_freq = 0.8 + bassReactivity * 1.5;
    float lfo1 = sin(time * lfo1_freq * 2.0 * M_PI_F);

    // Secondary LFO - Mid frequency synchronized (1-4 Hz)
    float lfo2_freq = 1.5 + midReactivity * 2.5;
    float lfo2 = cos(time * lfo2_freq * 2.0 * M_PI_F);

    // Tertiary LFO - Treble synchronized (2-8 Hz)
    float lfo3_freq = 3.0 + trebleReactivity * 5.0;
    float lfo3 = sin(time * lfo3_freq * 2.0 * M_PI_F + M_PI_F/2);

    // Quad LFO - Overall audio synchronized (0.2-1 Hz, very slow)
    float lfo4_freq = 0.3 + totalAudio * 0.7;
    float lfo4 = cos(time * lfo4_freq * 2.0 * M_PI_F + M_PI_F);

    // === CMYK COLOR SEPARATION ===
    // Sample base image
    float4 inputColor = inputTexture.read(gid);
    float3 baseColor = inputColor.rgb;

    // Convert RGB to CMYK-style separation
    float black_component = 1.0 - max(max(baseColor.r, baseColor.g), baseColor.b);
    float cyan_raw = (1.0 - baseColor.r - black_component) / (1.0 - black_component + 0.001);
    float magenta_raw = (1.0 - baseColor.g - black_component) / (1.0 - black_component + 0.001);
    float yellow_raw = (1.0 - baseColor.b - black_component) / (1.0 - black_component + 0.001);

    // === LFO MODULATED CMYK CHANNELS ===
    // Apply LFO modulation to each CMYK channel with different characteristics

    // Cyan channel - modulated by LFO1 (bass)
    float cyan_offset_x = lfo1 * bassReactivity * 8.0;
    float cyan_offset_y = lfo4 * bassReactivity * 4.0;
    uint2 cyan_coord = uint2(clamp(float2(gid) + float2(cyan_offset_x, cyan_offset_y),
                                  float2(0.0),
                                  float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1)));
    float3 cyan_sample = inputTexture.read(cyan_coord).rgb;
    float cyan_intensity = (1.0 - cyan_sample.r - black_component) / (1.0 - black_component + 0.001);
    cyan_intensity *= (0.7 + lfo1 * 0.3); // LFO modulated intensity

    // Magenta channel - modulated by LFO2 (mid)
    float magenta_offset_x = lfo2 * midReactivity * 6.0;
    float magenta_offset_y = lfo1 * midReactivity * 3.0;
    uint2 magenta_coord = uint2(clamp(float2(gid) + float2(magenta_offset_x, magenta_offset_y),
                                     float2(0.0),
                                     float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1)));
    float3 magenta_sample = inputTexture.read(magenta_coord).rgb;
    float magenta_intensity = (1.0 - magenta_sample.g - black_component) / (1.0 - black_component + 0.001);
    magenta_intensity *= (0.7 + lfo2 * 0.3); // LFO modulated intensity

    // Yellow channel - modulated by LFO3 (treble)
    float yellow_offset_x = lfo3 * trebleReactivity * 4.0;
    float yellow_offset_y = lfo2 * trebleReactivity * 6.0;
    uint2 yellow_coord = uint2(clamp(float2(gid) + float2(yellow_offset_x, yellow_offset_y),
                                    float2(0.0),
                                    float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1)));
    float3 yellow_sample = inputTexture.read(yellow_coord).rgb;
    float yellow_intensity = (1.0 - yellow_sample.b - black_component) / (1.0 - black_component + 0.001);
    yellow_intensity *= (0.7 + lfo3 * 0.3); // LFO modulated intensity

    // Black channel - modulated by LFO4 (overall audio)
    float black_offset_x = lfo4 * totalAudio * 2.0;
    float black_offset_y = lfo3 * totalAudio * 2.0;
    uint2 black_coord = uint2(clamp(float2(gid) + float2(black_offset_x, black_offset_y),
                                   float2(0.0),
                                   float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1)));
    float3 black_sample = inputTexture.read(black_coord).rgb;
    float black_intensity = 1.0 - max(max(black_sample.r, black_sample.g), black_sample.b);
    black_intensity *= (0.8 + lfo4 * 0.2); // LFO modulated intensity

    // === AUDIO-REACTIVE LFO AMPLITUDE MODULATION ===
    // Scale LFO effects based on audio intensity
    float audio_amp = smoothstep(0.05, 0.8, totalAudio);
    cyan_intensity = mix(cyan_raw, cyan_intensity, audio_amp);
    magenta_intensity = mix(magenta_raw, magenta_intensity, audio_amp);
    yellow_intensity = mix(yellow_raw, yellow_intensity, audio_amp);
    black_intensity = mix(black_component, black_intensity, audio_amp);

    // === CONVERT BACK TO RGB ===
    // Convert modulated CMYK back to RGB
    float3 finalColor;
    finalColor.r = (1.0 - cyan_intensity) * (1.0 - black_intensity);
    finalColor.g = (1.0 - magenta_intensity) * (1.0 - black_intensity);
    finalColor.b = (1.0 - yellow_intensity) * (1.0 - black_intensity);

    // === ADDITIONAL LFO EFFECTS ===
    // Add oscillating color enhancements based on audio
    if (totalAudio > 0.1) {
        // Oscillating saturation boost
        float saturation_lfo = sin(time * 4.0 + bassReactivity * 8.0) * totalAudio * 0.3;
        float3 gray = float3(dot(finalColor, float3(0.299, 0.587, 0.114)));
        finalColor = mix(gray, finalColor, 1.0 + saturation_lfo);

        // Oscillating brightness modulation
        float brightness_lfo = cos(time * 2.5 + midReactivity * 6.0) * totalAudio * 0.2;
        finalColor *= (1.0 + brightness_lfo);

        // Oscillating color temperature shift
        float temp_lfo = sin(time * 1.8 + trebleReactivity * 4.0) * totalAudio * 0.15;
        finalColor.r *= (1.0 + temp_lfo * 0.5);
        finalColor.b *= (1.0 - temp_lfo * 0.5);
    }

    // === FINAL OUTPUT ===
    // Clamp and output
    finalColor = clamp(finalColor, 0.0, 1.0);
    float4 outputColor = float4(finalColor, inputColor.a);
    outputTexture.write(outputColor, gid);
}

// === BAD TV EFFECT - Feedback Loop ===
// HSV conversion functions
float3 rgb2hsv(float3 c) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = c.g < c.b ? float4(c.b, c.g, K.w, K.z) : float4(c.g, c.b, K.x, K.y);
    float4 q = c.r < p.x ? float4(p.x, p.y, p.w, c.r) : float4(c.r, p.y, p.z, p.x);

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

kernel void badTVEffect(texture2d<float, access::read> inputTexture [[texture(0)]],
                       texture2d<float, access::write> outputTexture [[texture(1)]],
                       texture2d<float, access::read> feedbackTexture [[texture(2)]],
                       constant DiscoUniforms& uniforms [[buffer(0)]],
                       uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }

    const float pi = 3.14159265359;
    float2 resolution = float2(uniforms.resolutionX, uniforms.resolutionY);
    float2 loc = float2(gid) / resolution;

    // Audio-reactive parameters mapped to ISF inputs
    float audioLevel = uniforms.audioLevel;
    float bassLevel = uniforms.bassLevel;
    float midLevel = uniforms.midLevel;
    float trebleLevel = uniforms.trebleLevel;

    // Map audio to feedback parameters
    float2 preShift = float2(0.5 + bassLevel * 0.1, 0.5 + midLevel * 0.1);  // Slight audio-reactive shift
    float feedbackLevel = 0.9 + audioLevel * 0.1;  // 0.9-1.0 based on audio
    float rotateAngle = trebleLevel * 0.5;  // 0-0.5 rotation based on treble
    float zoomLevel = 1.2 + bassLevel * 0.8;  // 1.2-2.0 zoom based on bass
    float2 zoomCenter = float2(0.5, 0.5);  // Fixed center
    float2 feedbackShift = float2(0.5 + sin(uniforms.time) * 0.05, 0.5 + cos(uniforms.time) * 0.05);  // Time-based shift
    bool invert = false;  // No inversion
    int blendMode = 3;  // Max blend mode
    float blackThresh = 0.1;  // Fixed threshold
    float satLevel = 1.0 + midLevel;  // 1.0-2.0 saturation based on mids
    float colorShift = trebleLevel * 0.5;  // 0-0.5 color shift based on treble

    // Sample input pixel with preShift
    float2 inputLoc = loc + (0.5 - preShift);
    uint2 inputCoords = uint2(clamp(inputLoc * resolution, 0.0, resolution - 1.0));
    float4 inputPixelColor = inputTexture.read(inputCoords);

    float4 feedbackPixelColor = float4(0.0);

    // Apply rotation
    float2 rotLoc = loc * resolution;
    float r = distance(resolution/2.0, rotLoc);
    float a = atan2((rotLoc.y - resolution.y/2.0), (rotLoc.x - resolution.x/2.0));

    rotLoc.x = r * cos(a + 2.0 * pi * rotateAngle) + 0.5;
    rotLoc.y = r * sin(a + 2.0 * pi * rotateAngle) + 0.5;

    rotLoc = rotLoc / resolution + float2(0.5);

    // Apply zoom
    float2 modifiedCenter = zoomCenter;
    rotLoc.x = (rotLoc.x - modifiedCenter.x) * (1.0/zoomLevel) + modifiedCenter.x;
    rotLoc.y = (rotLoc.y - modifiedCenter.y) * (1.0/zoomLevel) + modifiedCenter.y;
    rotLoc += (0.5 - feedbackShift);

    // Sample feedback texture
    if (rotLoc.x < 0.0 || rotLoc.y < 0.0 || rotLoc.x > 1.0 || rotLoc.y > 1.0) {
        feedbackPixelColor = float4(0.0);
    } else {
        uint2 feedbackCoords = uint2(clamp(rotLoc * resolution, 0.0, resolution - 1.0));
        feedbackPixelColor = feedbackTexture.read(feedbackCoords);
    }

    // Apply color transformations to feedback
    feedbackPixelColor.rgb = rgb2hsv(feedbackPixelColor.rgb);
    feedbackPixelColor.r = fmod(feedbackPixelColor.r + colorShift, 1.0);
    feedbackPixelColor.g *= satLevel;
    feedbackPixelColor.rgb = hsv2rgb(feedbackPixelColor.rgb);

    if (invert) {
        feedbackPixelColor.rgb = 1.0 - feedbackPixelColor.rgb;
    }

    // Apply blend mode (Max blend mode = 3)
    if (blendMode == 0) {  // Add
        inputPixelColor = inputPixelColor + feedbackLevel * feedbackPixelColor;
    }
    else if (blendMode == 1) {  // Over Black
        float val = inputPixelColor.a * (inputPixelColor.r + inputPixelColor.g + inputPixelColor.b) / 3.0;
        inputPixelColor = (val >= blackThresh) ? inputPixelColor : feedbackLevel * feedbackPixelColor;
        inputPixelColor.a = inputPixelColor.a + feedbackPixelColor.a * feedbackLevel;
    }
    else if (blendMode == 2) {  // Over Alpha
        inputPixelColor.rgb = inputPixelColor.a * inputPixelColor.rgb + (1.0 - inputPixelColor.a) * feedbackLevel * feedbackPixelColor.rgb;
        inputPixelColor.a = inputPixelColor.a + feedbackPixelColor.a * feedbackLevel;
    }
    else if (blendMode == 3) {  // Max
        inputPixelColor.rgb = max(inputPixelColor.a * inputPixelColor.rgb, feedbackLevel * feedbackPixelColor.rgb);
        inputPixelColor.a = inputPixelColor.a + feedbackPixelColor.a * feedbackLevel;
    }
    else if (blendMode == 4) {  // Under Black
        float val = feedbackPixelColor.a * (feedbackPixelColor.r + feedbackPixelColor.g + feedbackPixelColor.b) / 3.0;
        inputPixelColor = (val < blackThresh) ? inputPixelColor.a * inputPixelColor : feedbackLevel * feedbackPixelColor;
        inputPixelColor.a = inputPixelColor.a + feedbackPixelColor.a * feedbackLevel;
    }
    else if (blendMode == 5) {  // Under Alpha
        inputPixelColor.rgb = (1.0 - feedbackPixelColor.a) * inputPixelColor.a * inputPixelColor.rgb + feedbackLevel * feedbackPixelColor.rgb;
        inputPixelColor.a = inputPixelColor.a + feedbackPixelColor.a * feedbackLevel;
    }

    outputTexture.write(inputPixelColor, gid);
}

// === STROBE EFFECT ===
kernel void strobeEffect(texture2d<float, access::read> inputTexture [[texture(0)]],
                         texture2d<float, access::write> outputTexture [[texture(1)]],
                         texture2d<float, access::read_write> strobeStateTexture [[texture(2)]],
                         constant DiscoUniforms& uniforms [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }

    float2 resolution = float2(uniforms.resolutionX, uniforms.resolutionY);
    float time = uniforms.time;

    // Audio-reactive parameters mapped to ISF inputs
    float audioLevel = uniforms.audioLevel;
    float bassLevel = uniforms.bassLevel;
    float midLevel = uniforms.midLevel;
    float trebleLevel = uniforms.trebleLevel;

    // Map audio to strobe parameters
    bool r = true;  // Red channel enabled
    bool g = true;  // Green channel enabled
    bool b = true;  // Blue channel enabled
    bool a = false; // Alpha channel disabled

    // Audio-reactive strobe rates (in seconds per cycle)
    float4 strobeRates = float4(
        bassLevel > 0.1 ? (0.1 + bassLevel * 0.9) : 0.0,      // Red controlled by bass
        midLevel > 0.1 ? (0.15 + midLevel * 0.85) : 0.0,      // Green controlled by mids
        trebleLevel > 0.1 ? (0.05 + trebleLevel * 0.45) : 0.0, // Blue controlled by treble
        0.0  // Alpha disabled
    );

    // Read current strobe state (1x1 texture at center)
    float4 currentState = strobeStateTexture.read(uint2(0, 0));

    // Update strobe state based on time and rates
    float4 newState;

    // Red channel strobe logic
    if (strobeRates.r == 0.0) {
        newState.r = (currentState.r == 0.0) ? 1.0 : 0.0;  // Toggle on silence
    } else {
        newState.r = (fmod(time, strobeRates.r) <= strobeRates.r / 2.0) ? 1.0 : 0.0;
    }

    // Green channel strobe logic
    if (strobeRates.g == 0.0) {
        newState.g = (currentState.g == 0.0) ? 1.0 : 0.0;  // Toggle on silence
    } else {
        newState.g = (fmod(time, strobeRates.g) <= strobeRates.g / 2.0) ? 1.0 : 0.0;
    }

    // Blue channel strobe logic
    if (strobeRates.b == 0.0) {
        newState.b = (currentState.b == 0.0) ? 1.0 : 0.0;  // Toggle on silence
    } else {
        newState.b = (fmod(time, strobeRates.b) <= strobeRates.b / 2.0) ? 1.0 : 0.0;
    }

    // Alpha channel strobe logic
    if (strobeRates.a == 0.0) {
        newState.a = (currentState.a == 0.0) ? 1.0 : 0.0;  // Toggle on silence
    } else {
        newState.a = (fmod(time, strobeRates.a) <= strobeRates.a / 2.0) ? 1.0 : 0.0;
    }

    // Update state texture (only one thread should do this)
    if (gid.x == 0 && gid.y == 0) {
        strobeStateTexture.write(newState, uint2(0, 0));
    }

    // Apply strobe effect to input pixel
    float4 inputPixel = inputTexture.read(gid);
    float4 outputPixel = inputPixel;

    // Channel enable/disable values
    float red = r ? 1.0 : 0.0;
    float green = g ? 1.0 : 0.0;
    float blue = b ? 1.0 : 0.0;
    float alpha = a ? 1.0 : 0.0;

    // Apply strobe effect per channel
    outputPixel.r = (newState.r == 0.0) ? inputPixel.r : abs(red - inputPixel.r);
    outputPixel.g = (newState.g == 0.0) ? inputPixel.g : abs(green - inputPixel.g);
    outputPixel.b = (newState.b == 0.0) ? inputPixel.b : abs(blue - inputPixel.b);
    outputPixel.a = (newState.a == 0.0) ? inputPixel.a : abs(alpha - inputPixel.a);

    outputTexture.write(outputPixel, gid);
}

// Convergence Effect - RGB channel separation with chromatic aberration
// Random function for convergence effect
float convergenceRand(float2 co) {
    return fract(sin(dot(co.xy, float2(12.9898, 78.233))) * 43758.5453);
}

kernel void convergenceEffect(texture2d<float, access::read> inputTexture [[ texture(0) ]],
                             texture2d<float, access::write> outputTexture [[ texture(1) ]],
                             constant float &time [[ buffer(0) ]],
                             constant float &horizontal_magnitude [[ buffer(1) ]],
                             constant float &vertical_magnitude [[ buffer(2) ]],
                             constant float &color_magnitude [[ buffer(3) ]],
                             constant int &mode [[ buffer(4) ]],
                             uint2 gid [[ thread_position_in_grid ]]) {

    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }

    float2 texCoord = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());

    // Read original pixel
    float4 col = inputTexture.read(gid);

    uint width = inputTexture.get_width();
    uint height = inputTexture.get_height();

    // Audio-reactive RGB separation - scaled to stay on screen
    // Red channel offset (horizontal + vertical displacement)
    float2 red_offset = texCoord + float2(horizontal_magnitude * 0.08, vertical_magnitude * 0.05);
    uint2 offset_r = uint2(clamp(red_offset.x * width, 0.0, float(width-1)),
                          clamp(red_offset.y * height, 0.0, float(height-1)));
    float4 col_r = inputTexture.read(offset_r);

    // Blue channel offset (opposite horizontal + opposite vertical displacement)
    float2 blue_offset = texCoord + float2(-horizontal_magnitude * 0.08, -vertical_magnitude * 0.05);
    uint2 offset_l = uint2(clamp(blue_offset.x * width, 0.0, float(width-1)),
                          clamp(blue_offset.y * height, 0.0, float(height-1)));
    float4 col_l = inputTexture.read(offset_l);

    // Green channel offset (both horizontal and vertical displacement)
    float2 green_offset = texCoord + float2(horizontal_magnitude * 0.05, vertical_magnitude * 0.07);
    uint2 offset_g = uint2(clamp(green_offset.x * width, 0.0, float(width-1)),
                          clamp(green_offset.y * height, 0.0, float(height-1)));
    float4 col_g = inputTexture.read(offset_g);

    // Create convergence effect by combining separated RGB channels
    float4 separated_channels;
    separated_channels.r = col_r.r;  // Red from offset sample
    separated_channels.g = col_g.g;  // Green from offset sample
    separated_channels.b = col_l.b;  // Blue from offset sample
    separated_channels.a = col.a;    // Keep original alpha

    // Apply blend mode
    float4 result;
    if (mode == 0) {
        // Add
        result = col + separated_channels * color_magnitude * 0.3;
    } else if (mode == 1) {
        // Add mod - creates psychedelic color wrapping
        result = fmod(col + separated_channels * color_magnitude * 0.8, 1.001);
    } else if (mode == 2) {
        // Multiply
        result = col * separated_channels * color_magnitude;
    } else {
        // Difference (mode == 3)
        result = abs(separated_channels - col) * color_magnitude;
    }

    outputTexture.write(result, gid);
}

// Alpha blending shader for crossfader mixing
kernel void alphaBlendEffects(texture2d<float, access::read> leftTexture [[texture(0)]],
                             texture2d<float, access::read> rightTexture [[texture(1)]],
                             texture2d<float, access::write> outputTexture [[texture(2)]],
                             constant float& leftAlpha [[buffer(0)]],
                             constant float& rightAlpha [[buffer(1)]],
                             uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }

    // Read pixels from both effect textures
    float4 leftPixel = leftTexture.read(gid);
    float4 rightPixel = rightTexture.read(gid);

    // Perform alpha blending: result = leftPixel * leftAlpha + rightPixel * rightAlpha
    float4 blendedPixel = leftPixel * leftAlpha + rightPixel * rightAlpha;

    // Ensure alpha channel is 1.0 for proper display
    blendedPixel.a = 1.0;

    outputTexture.write(blendedPixel, gid);
}

// MARK: - Tunnel Effect
kernel void tunnelEffect(texture2d<float, access::read> inputTexture [[texture(0)]],
                         texture2d<float, access::write> outputTexture [[texture(1)]],
                         constant DiscoUniforms& uniforms [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }

    float4 inputColor = inputTexture.read(gid);
    float2 resolution = float2(uniforms.resolutionX, uniforms.resolutionY);
    float2 uv = float2(gid) / resolution;
    float2 center = float2(0.5, 0.5);

    // Create concentric squares tunnel
    float time = uniforms.time * 12.0 + uniforms.audioLevel * 8.0;
    float2 p = abs(uv - center);
    float distance = max(p.x, p.y); // Square distance

    // Audio-reactive tunnel parameters
    float tunnelSpeed = 2.0 + uniforms.bassLevel * 15.0;
    float tunnelDepth = 6.0 + uniforms.midLevel * 20.0;
    float colorShift = uniforms.trebleLevel * 10.0;

    // Create infinite tunnel effect
    float layer = fract(distance * tunnelDepth - time * tunnelSpeed);
    float edge = smoothstep(0.05, 0.15, layer) * smoothstep(0.95, 0.85, layer);

    // Audio-reactive colors
    float3 color1 = float3(0.8 + uniforms.bassLevel * 0.2, 0.2, 0.9);
    float3 color2 = float3(0.2, 0.8 + uniforms.midLevel * 0.2, 0.9);
    float3 color3 = float3(0.9, 0.2, 0.8 + uniforms.trebleLevel * 0.2);

    // Cycle through colors based on depth and audio
    float colorCycle = sin(time * 0.5 + distance * 8.0 + colorShift) * 0.5 + 0.5;
    float3 tunnelColor = mix(color1, color2, colorCycle);
    tunnelColor = mix(tunnelColor, color3, sin(colorCycle * 3.14159 + time) * 0.5 + 0.5);

    // Apply tunnel effect
    float3 finalColor = mix(inputColor.rgb, tunnelColor, edge * uniforms.intensity);

    // Audio-reactive brightness modulation
    float brightness = 1.0 + sin(time * 2.0) * uniforms.audioLevel * 0.3;
    finalColor *= brightness;

    outputTexture.write(float4(finalColor, inputColor.a), gid);
}

// MARK: - Kaleidoscope Effect
kernel void kaleidoscopeEffect(texture2d<float, access::read> inputTexture [[texture(0)]],
                              texture2d<float, access::write> outputTexture [[texture(1)]],
                              constant DiscoUniforms& uniforms [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }

    float2 resolution = float2(uniforms.resolutionX, uniforms.resolutionY);
    float2 uv = float2(gid) / resolution;
    float2 center = float2(0.5, 0.5);

    // Audio-reactive rotation
    float rotation = uniforms.time * 0.5 + uniforms.audioLevel * 5.0;
    float rotCos = cos(rotation);
    float rotSin = sin(rotation);

    // Transform coordinates to center
    float2 p = uv - center;

    // Apply rotation matrix
    float2 rotated = float2(
        p.x * rotCos - p.y * rotSin,
        p.x * rotSin + p.y * rotCos
    );

    // Create bilateral mirror symmetry (kaleidoscope effect)
    rotated = abs(rotated);

    // Audio-reactive scaling
    float scale = 1.0 + uniforms.bassLevel * 2.0;
    rotated *= scale;

    // Fold space for kaleidoscope segments
    float angle = atan2(rotated.y, rotated.x);
    float radius = length(rotated);

    // Create 6-fold symmetry with audio reactivity
    float segments = 6.0 + uniforms.midLevel * 6.0;
    angle = abs(fmod(angle, 2.0 * 3.14159 / segments));
    if (angle > 3.14159 / segments) {
        angle = 2.0 * 3.14159 / segments - angle;
    }

    // Convert back to cartesian
    rotated = float2(cos(angle), sin(angle)) * radius;

    // Sample texture with mirrored coordinates
    float2 sampleUV = fmod(abs(rotated) + center, 1.0);

    // Ensure UV coordinates are within bounds
    sampleUV = clamp(sampleUV, 0.0, 1.0);
    uint2 sampleCoord = uint2(sampleUV * resolution);
    sampleCoord = clamp(sampleCoord, uint2(0), uint2(inputTexture.get_width() - 1, inputTexture.get_height() - 1));

    float4 kaleidoColor = inputTexture.read(sampleCoord);

    // Audio-reactive color enhancement
    float3 colorMod = float3(
        1.0 + uniforms.bassLevel * 0.5,
        1.0 + uniforms.midLevel * 0.5,
        1.0 + uniforms.trebleLevel * 0.5
    );
    kaleidoColor.rgb *= colorMod;

    // Intensity modulation
    float intensity = uniforms.intensity * (0.8 + uniforms.audioLevel * 0.4);
    float4 inputColor = inputTexture.read(gid);
    float4 finalColor = mix(inputColor, kaleidoColor, intensity);

    outputTexture.write(finalColor, gid);
}

// MARK: - Analog Glitch Effect
kernel void analogGlitchEffect(texture2d<float, access::read> inputTexture [[texture(0)]],
                              texture2d<float, access::write> outputTexture [[texture(1)]],
                              constant DiscoUniforms& uniforms [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }

    float4 inputColor = inputTexture.read(gid);
    float2 resolution = float2(uniforms.resolutionX, uniforms.resolutionY);
    float2 uv = float2(gid) / resolution;

    // Audio-reactive glitch parameters
    float time = uniforms.time * 8.0;
    float glitchIntensity = uniforms.intensity * (0.5 + uniforms.audioLevel * 1.5);
    float scanlineSpeed = 10.0 + uniforms.bassLevel * 30.0;
    float noiseAmount = 0.1 + uniforms.midLevel * 0.4;
    float colorBleed = uniforms.trebleLevel * 0.3;

    // VHS-style horizontal distortion
    float scanline = sin(uv.y * 800.0 + time * scanlineSpeed) * 0.5 + 0.5;
    float distortion = sin(uv.y * 20.0 + time * 2.0) * glitchIntensity * 0.02;

    // Audio-reactive horizontal shift
    float shift = sin(time * 0.5 + uniforms.audioLevel * 10.0) * glitchIntensity * 0.05;
    float2 shiftedUV = uv + float2(distortion + shift, 0.0);

    // Clamp UV coordinates
    shiftedUV = clamp(shiftedUV, 0.0, 1.0);
    uint2 shiftedCoord = uint2(shiftedUV * resolution);
    shiftedCoord = clamp(shiftedCoord, uint2(0), uint2(inputTexture.get_width() - 1, inputTexture.get_height() - 1));

    float4 shiftedColor = inputTexture.read(shiftedCoord);

    // RGB channel separation (chromatic aberration)
    float2 redUV = uv + float2(colorBleed, 0.0);
    float2 blueUV = uv - float2(colorBleed, 0.0);

    redUV = clamp(redUV, 0.0, 1.0);
    blueUV = clamp(blueUV, 0.0, 1.0);

    uint2 redCoord = clamp(uint2(redUV * resolution), uint2(0), uint2(inputTexture.get_width() - 1, inputTexture.get_height() - 1));
    uint2 blueCoord = clamp(uint2(blueUV * resolution), uint2(0), uint2(inputTexture.get_width() - 1, inputTexture.get_height() - 1));

    float redChannel = inputTexture.read(redCoord).r;
    float greenChannel = shiftedColor.g;
    float blueChannel = inputTexture.read(blueCoord).b;

    // Analog noise
    float noise = fract(sin(dot(uv + time * 0.1, float2(12.9898, 78.233))) * 43758.5453);
    noise = (noise - 0.5) * noiseAmount;

    // Video interference lines
    float interference = step(0.98, sin(uv.y * 200.0 + time * 50.0));
    interference *= glitchIntensity;

    // Combine effects
    float3 glitchColor = float3(redChannel, greenChannel, blueChannel);
    glitchColor += noise;
    glitchColor = mix(glitchColor, float3(1.0), interference * 0.3);

    // Scanline effect
    glitchColor *= (0.8 + scanline * 0.4);

    // Audio-reactive brightness modulation
    float brightness = 1.0 + sin(time * 1.5) * uniforms.audioLevel * 0.2;
    glitchColor *= brightness;

    // Mix with original based on intensity
    float3 finalColor = mix(inputColor.rgb, glitchColor, glitchIntensity);

    outputTexture.write(float4(finalColor, inputColor.a), gid);
}

