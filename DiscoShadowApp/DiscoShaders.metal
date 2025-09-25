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

// MARK: - VHS Datamoshing Effect (Premium)
kernel void crtSlitScanEffect(texture2d<float, access::read> inputTexture [[texture(0)]],
                              texture2d<float, access::write> outputTexture [[texture(1)]],
                              constant DiscoUniforms &uniforms [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }

    float2 uv = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    float4 inputColor = inputTexture.read(gid);

    // Enhanced audio responsiveness with frequency separation
    float bassReactivity = uniforms.bassLevel * uniforms.intensity * 2.0;
    float midReactivity = uniforms.midLevel * uniforms.intensity * 1.5;
    float trebleReactivity = uniforms.trebleLevel * uniforms.intensity * 1.2;
    float totalAudio = uniforms.audioLevel * uniforms.intensity * 2.5;

    // Create different strength levels for different effects
    float shakeStrength = clamp(bassReactivity + totalAudio * 0.8, 0.0, 1.0);
    float glitchStrength = clamp(midReactivity + totalAudio * 0.6, 0.0, 1.0);
    float noiseStrength = clamp(trebleReactivity + totalAudio * 0.4, 0.0, 1.0);

    // Time-based effects with audio modulation
    float time = uniforms.time + totalAudio * 10.0; // Audio speeds up time

    // === AUDIO-REACTIVE VHS SHAKE EFFECT ===
    // Shake responds to bass and overall audio level
    float audioShakeIntensity = smoothstep(0.5, 3.0, 3.0 - fmod(time, 3.0)) * (shakeStrength * 15.0 + 0.5);

    // Add instant audio spikes for more dramatic shake
    float audioSpike = step(0.7, uniforms.bassLevel) * uniforms.bassLevel * 20.0;
    audioShakeIntensity += audioSpike;

    float2 shake = float2(
        (fract(sin(time * 12.9898 + bassReactivity * 100.0) * 43758.5453) * 2.0 - 1.0),
        (fract(sin(time * 78.233 + midReactivity * 80.0) * 43758.5453) * 2.0 - 1.0)
    ) * audioShakeIntensity / float2(outputTexture.get_width(), outputTexture.get_height());

    // === RGB WAVE DISPLACEMENT ===
    // Simplex noise approximation for wave displacement
    float y = uv.y * float(outputTexture.get_height());
    float rgbWave = (
        sin(y * 0.01 + time * 4.0) * (2.0 + glitchStrength * 32.0) *
        sin(y * 0.02 + time * 2.0) * (1.0 + glitchStrength * 4.0) +
        step(0.9995, sin(y * 0.005 + time * 1.6)) * 12.0 +
        step(0.9999, sin(y * 0.005 + time * 2.0)) * -18.0
    ) / float(outputTexture.get_width());

    float rgbDiff = (6.0 + sin(time * 50.0 + uv.y * 40.0) * (20.0 * glitchStrength + 1.0)) / float(outputTexture.get_width());
    float rgbUvX = uv.x + rgbWave;

    // === CHROMATIC ABERRATION with RGB SEPARATION ===
    // Sample RGB channels with different offsets (like the JS version)
    float2 shakeUV = uv + shake;

    uint2 redCoord = uint2(clamp((shakeUV + float2(rgbUvX + rgbDiff, uv.y)) * float2(inputTexture.get_width(), inputTexture.get_height()),
                                 float2(0.0),
                                 float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1)));
    uint2 greenCoord = uint2(clamp((shakeUV + float2(rgbUvX, uv.y)) * float2(inputTexture.get_width(), inputTexture.get_height()),
                                   float2(0.0),
                                   float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1)));
    uint2 blueCoord = uint2(clamp((shakeUV + float2(rgbUvX - rgbDiff, uv.y)) * float2(inputTexture.get_width(), inputTexture.get_height()),
                                  float2(0.0),
                                  float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1)));

    float r = inputTexture.read(redCoord).r;
    float g = inputTexture.read(greenCoord).g;
    float b = inputTexture.read(blueCoord).b;

    // === WHITE NOISE ===
    float whiteNoise = (fract(sin(dot(uv + fmod(time, 10.0), float2(12.9898, 78.233))) * 43758.5453) * 2.0 - 1.0) * (0.15 + noiseStrength * 0.15);

    // === BLOCK NOISE (First Layer) ===
    float bnTime = floor(time * 20.0) * 200.0;
    float noiseX = step(0.12 + glitchStrength * 0.3, (sin(uv.x * 3.0 + bnTime) + 1.0) / 2.0);
    float noiseY = step(0.12 + glitchStrength * 0.3, (sin(uv.y * 3.0 + bnTime) + 1.0) / 2.0);
    float bnMask = noiseX * noiseY;

    float bnUvX = uv.x + sin(bnTime) * 0.2 + rgbWave;

    uint2 bnRedCoord = uint2(clamp(float2(bnUvX + rgbDiff, uv.y) * float2(inputTexture.get_width(), inputTexture.get_height()),
                                   float2(0.0),
                                   float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1)));
    uint2 bnGreenCoord = uint2(clamp(float2(bnUvX, uv.y) * float2(inputTexture.get_width(), inputTexture.get_height()),
                                     float2(0.0),
                                     float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1)));
    uint2 bnBlueCoord = uint2(clamp(float2(bnUvX - rgbDiff, uv.y) * float2(inputTexture.get_width(), inputTexture.get_height()),
                                    float2(0.0),
                                    float2(inputTexture.get_width() - 1, inputTexture.get_height() - 1)));

    float bnR = inputTexture.read(bnRedCoord).r * bnMask;
    float bnG = inputTexture.read(bnGreenCoord).g * bnMask;
    float bnB = inputTexture.read(bnBlueCoord).b * bnMask;
    float3 blockNoise = float3(bnR, bnG, bnB);

    // === BLOCK NOISE (Second Layer) ===
    float bnTime2 = floor(time * 25.0) * 300.0;
    float noiseX2 = step(0.12 + glitchStrength * 0.5, (sin(uv.x * 2.0 + bnTime2) + 1.0) / 2.0);
    float noiseY2 = step(0.12 + glitchStrength * 0.3, (sin(uv.y * 8.0 + bnTime2) + 1.0) / 2.0);
    float bnMask2 = noiseX2 * noiseY2;

    float bnR2 = inputTexture.read(bnRedCoord).r * bnMask2;
    float bnG2 = inputTexture.read(bnGreenCoord).g * bnMask2;
    float bnB2 = inputTexture.read(bnBlueCoord).b * bnMask2;
    float3 blockNoise2 = float3(bnR2, bnG2, bnB2);

    // === WAVE NOISE ===
    float waveNoise = (sin(uv.y * 1200.0) + 1.0) / 2.0 * (0.15 + noiseStrength * 0.2);

    // === FINAL VHS DATAMOSHING COMPOSITE ===
    // Combine all effects like the JavaScript version
    float3 baseColor = float3(r, g, b);

    // Apply the JS formula: baseColor * (1.0 - masks) + noise effects
    float3 finalColor = baseColor * (1.0 - bnMask - bnMask2) +
                       float3(whiteNoise) + blockNoise + blockNoise2 - float3(waveNoise);

    // Add VHS-style scanlines
    float scanlineFreq = 300.0 + glitchStrength * 200.0; // Bigger scanlines as requested
    float scanlines = (sin(uv.y * scanlineFreq) + 1.0) / 2.0;
    finalColor *= (scanlines * 0.3 + 0.7); // Subtle scanline effect

    // VHS color grading - desaturate and add vintage tint
    float luminance = dot(finalColor, float3(0.299, 0.587, 0.114));
    finalColor = mix(float3(luminance), finalColor, 0.8); // Desaturate slightly
    finalColor *= float3(1.05, 0.95, 0.9); // Warm vintage tint

    // Add VHS tape flutter effect
    float flutter = sin(time * 15.0 + uv.y * 50.0) * 0.02 * totalAudio;
    finalColor += float3(flutter * 0.1, flutter * 0.05, flutter * -0.05);

    // Clamp to valid range
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

    // Audio-reactive intensity and pulsing
    float intensity = 1.0 + sin(time * 4.0) * audioReactivity * 0.4;
    pattern_color *= intensity;

    // Pattern strength for blending - stronger at edges for better following
    float pattern_strength = 0.85 + audioReactivity * 0.4 + edge_strength * 0.3;

    // === ENHANCED AUDIO-REACTIVE CHROMATIC ABERRATIONS ===
    // Multi-layered aberration with different frequency responses
    float base_aberration = audioReactivity * uniforms.chromaticAberration * 25.0;

    // Bass creates large horizontal shifts (like vinyl warping)
    float2 bass_offset = float2(
        sin(time * 2.0 + uniforms.bassLevel * 8.0) * uniforms.bassLevel * 0.08,
        cos(time * 1.5 + uniforms.bassLevel * 6.0) * uniforms.bassLevel * 0.04
    );

    // Mids create circular/orbital motion
    float mid_angle = time * 4.0 + uniforms.midLevel * 12.0;
    float2 mid_offset = float2(
        cos(mid_angle) * uniforms.midLevel * 0.06,
        sin(mid_angle) * uniforms.midLevel * 0.06
    );

    // Treble creates rapid jittery movements
    float2 treble_offset = float2(
        sin(time * 15.0 + r * 20.0) * uniforms.trebleLevel * 0.04,
        cos(time * 18.0 + r * 25.0) * uniforms.trebleLevel * 0.03
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

    // Enhanced audio-reactive HSV for each channel with expanded hue range
    float hue_red = 0.0 + r_red * (6.0 + uniforms.bassLevel * 8.0) + time * 0.5 + sin(uniforms.bassLevel * 15.0) * 0.4;
    float hue_green = 0.33 + r_green * (7.0 + uniforms.midLevel * 6.0) + time * 0.4 + cos(uniforms.midLevel * 12.0) * 0.35;
    float hue_blue = 0.66 + r_blue * (8.0 + uniforms.trebleLevel * 7.0) + time * 0.3 + sin(uniforms.trebleLevel * 18.0) * 0.45;

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

    // Smooth edge strength to avoid harsh transitions
    edge_strength = smoothstep(0.1, 0.5, edge_strength);

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

    // Layer 3: Frequency modulation waves
    float freq_mod = 3.0 + sin(time * 0.5) * 2.0 + audioReactivity * 4.0;
    float wave_layer3 = cos(uv.x * freq_mod + sin(uv.y * freq_mod * 1.2) + A * 0.6) +
                        sin(uv.y * freq_mod * 0.9 + cos(uv.x * freq_mod * 1.1) + B * 1.2);

    // Layer 4: Spiral patterns
    float wave_layer4 = sin(spiral_angle * (8.0 + uniforms.trebleLevel * 6.0) +
                           spiral_radius * (20.0 + uniforms.bassLevel * 10.0) + C);

    // Layer 5: Moiré interference patterns
    float moire_freq1 = 15.0 + uniforms.bassLevel * 8.0;
    float moire_freq2 = 16.0 + uniforms.trebleLevel * 9.0;
    float wave_layer5 = (sin(uv.x * moire_freq1 + time * 2.0) * sin(uv.y * moire_freq1 + A)) +
                        (cos(uv.x * moire_freq2 + time * 1.3) * cos(uv.y * moire_freq2 + B));

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

    // === EDGE-GUIDED WAVE DISTORTION ===
    // Base audio-reactive waves
    float2 wave_distortion = float2(0.0);
    wave_distortion.x += sin(uv.y * 8.0 + time * 2.0) * uniforms.bassLevel * 0.05;
    wave_distortion.y += cos(uv.x * 12.0 + time * 1.5) * uniforms.trebleLevel * 0.03;
    wave_distortion += sin(uv * 6.0 + time) * uniforms.midLevel * 0.02;

    // Edge-following wave modulation
    float edge_wave_strength = edge_strength * (0.3 + audioReactivity * 0.4);

    // Make waves follow edge direction with Op-Art pattern modulation
    float edge_wave_phase = time * 3.0 + edge_strength * 10.0;
    float2 edge_wave_offset = edge_direction * sin(edge_wave_phase) * edge_wave_strength;

    // Add perpendicular wave motion for more dynamic edge following
    float2 perp_direction = float2(-edge_direction.y, edge_direction.x);
    float2 perp_wave_offset = perp_direction * cos(edge_wave_phase * 1.3) * edge_wave_strength * 0.6;

    // Combine edge-guided waves with base distortion
    wave_distortion += edge_wave_offset + perp_wave_offset;

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

    float4 outputColor = float4(finalColor, inputColor.a);
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


