# Fever Dream
### Psychedelic Camera Effects & Music-Reactive Visuals for iOS

<div align="center">

![iOS](https://img.shields.io/badge/iOS-17.0+-blue)
![SwiftUI](https://img.shields.io/badge/SwiftUI-5.0+-green)
![Metal](https://img.shields.io/badge/Metal-3.0+-orange)
![MusicKit](https://img.shields.io/badge/MusicKit-Apple-red)
![StoreKit](https://img.shields.io/badge/StoreKit-2.0-purple)

*Real-time psychedelic visual effects powered by Metal shaders and audio-reactive processing*

</div>

## 🌈 Overview

Fever Dream is an iOS camera app that transforms reality into mesmerizing psychedelic experiences. Built with SwiftUI, Metal, and advanced audio processing, it offers real-time visual effects, music integration, and a premium subscription model.

## ✨ Key Features

### 🎥 Real-time Visual Effects
- **Metal-powered shaders** for high-performance GPU rendering
- **Audio-reactive visuals** that respond to music and microphone input
- **Multiple effect modes** including kaleidoscope, CRT glitch, and disco patterns
- **Crossfader functionality** for seamless effect transitions
- **Live camera feed processing** with zero latency

### 🎵 Music Integration
- **Apple Music integration** via MusicKit
- **Instagram-style music browser** for song discovery
- **Volume control** with visual feedback
- **Audio waveform analysis** for reactive effects
- **Imported media support** for custom soundtracks

### 📱 Native iOS Features
- **SwiftUI interface** with magenta/cyan theme
- **Camera controls** with zoom, focus, and exposure
- **Photo & video capture** with effects applied
- **Media gallery** with playback and sharing
- **Portrait orientation** optimized UI

### 💎 Premium Subscription
- **StoreKit 2 integration** with secure transactions
- **Monthly subscription** ($1.99/month) with 1-month free trial
- **Premium effects** unlocked with subscription
- **Restore purchases** functionality
- **Face ID authentication** for frictionless upgrades

## 🏗 Technical Architecture

### Core Components

```
DiscoShadowApp/
├── 📱 App Structure
│   ├── DiscoShadowApp.swift      # Main app entry point
│   ├── ContentView.swift         # Primary UI and camera view
│   └── EffectMixerView.swift     # Crossfader interface
│
├── 📷 Camera & Recording
│   ├── CameraManager.swift       # AVFoundation camera handling
│   ├── VideoEffectsProcessor.swift # Core video processing
│   ├── MetalRenderer.swift       # Metal GPU rendering engine
│   └── DiscoShaders.metal        # GPU shader programs
│
├── 🎵 Audio & Music
│   ├── AudioManager.swift        # Audio capture and processing
│   ├── MusicAPIService.swift     # Apple Music integration
│   ├── MusicPlayerService.swift  # Playback control
│   ├── SimpleMusicManager.swift  # Music management
│   └── InstagramStyleMusicBrowser.swift # Music discovery UI
│
├── 💰 Monetization
│   ├── StoreManager.swift        # StoreKit 2 subscription handling
│   └── PremiumMenuView.swift     # Premium upgrade interface
│
├── 📁 Media Management
│   ├── VideoGalleryView.swift    # Media library and playback
│   ├── MediaImportView.swift     # Photo/video import
│   └── ImportedMediaRecordingView.swift # Custom media recording
│
└── 📋 Configuration
    ├── MusicKitConfig.swift      # Apple Music API credentials
    └── Info.plist               # Privacy permissions and app config
```

### Technology Stack

- **SwiftUI** - Modern declarative UI framework
- **Metal** - High-performance GPU computing and rendering
- **AVFoundation** - Camera, audio capture, and media processing
- **MusicKit** - Apple Music API integration
- **StoreKit 2** - In-app purchases and subscriptions
- **CoreImage** - Image processing pipelines
- **Combine** - Reactive programming for data flow

## 🚀 Quick Start

### Prerequisites
- **Xcode 16+** (iOS 18 SDK required for TestFlight)
- **macOS 14.2+**
- **iOS 17.0+** target device
- **Apple Developer Account** (for App Store distribution)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/feverdreaminteractive/fever-dream-app.git
   cd fever-dream-app
   ```

2. **Open in Xcode**
   ```bash
   open DiscoShadowApp.xcodeproj
   ```

3. **Configure signing**
   - Select your development team
   - Update bundle identifier if needed
   - Ensure provisioning profiles are valid

4. **Build and run**
   - Connect iOS device (Metal requires physical hardware)
   - Select device as destination
   - Build and run (⌘R)

### Required Permissions

The app requires the following iOS permissions (configured in `Info.plist`):

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required to capture photos and videos with real-time effects</string>

<key>NSMicrophoneUsageDescription</key>
<string>Microphone access enables audio-reactive visual effects</string>

<key>NSAppleMusicUsageDescription</key>
<string>Music access allows browsing and playing songs for audio-reactive effects</string>
```

## 🎨 Visual Effects System

### Available Effects

| Effect | Description | Premium |
|--------|-------------|---------|
| **Fever Dream** | Classic disco kaleidoscope (default) | ❌ |
| **CRT Dither Glitch** | Retro CRT monitor simulation | ✅ |
| **Hypnotist** | Spiral hypnotic patterns | ✅ |
| **More effects** | Additional premium effects | ✅ |

### Shader Development

Effects are implemented as Metal shaders in `DiscoShaders.metal`:

```metal
// Example effect fragment shader
fragment float4 feverDreamEffect(
    VertexOut in [[stage_in]],
    texture2d<float> inputTexture [[texture(0)]],
    constant float &time [[buffer(0)]],
    constant float2 &audioData [[buffer(1)]]
) {
    // GPU-accelerated visual processing
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    float2 uv = in.textureCoordinate;

    // Audio-reactive transformations
    float audioIntensity = audioData.x;
    float2 center = float2(0.5, 0.5);
    float2 delta = uv - center;
    float angle = atan2(delta.y, delta.x) + time * audioIntensity;

    // Kaleidoscope effect
    float radius = length(delta);
    float2 kaleidoUV = center + radius * float2(cos(angle), sin(angle));

    return inputTexture.sample(textureSampler, kaleidoUV);
}
```

## 💰 Subscription System

### StoreKit 2 Integration

The app implements a robust subscription system:

- **Product ID**: `fever_dream_subscription_monthly`
- **Price**: $1.99/month
- **Free Trial**: 1 month for new subscribers
- **Billing**: Auto-renewable through Apple

### Revenue Model

- **Apple's Cut**: 30% (first year), 15% (retained subscribers)
- **Net Revenue**: ~$1.39/month (first year), ~$1.69/month (after)
- **Premium Features**: Advanced effects, exclusive content

### Implementation

```swift
@MainActor
class StoreManager: NSObject, ObservableObject {
    @Published var hasSubscription = false

    func purchaseSubscription() async throws {
        guard let product = products.first else { return }
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            await handleSuccessfulPurchase(verification)
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }
}
```

## 🎵 Music Integration

### Apple Music Features

- **MusicKit API** for official Apple Music integration
- **Song search** and trending discovery
- **Playback control** with volume adjustment
- **Audio analysis** for reactive visual effects

### Usage Example

```swift
@available(iOS 15.0, *)
class MusicAPIService: ObservableObject {
    func searchSongs(_ query: String) async throws -> [Song] {
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
        request.limit = 25

        let response = try await request.response()
        return Array(response.songs)
    }
}
```

## 📱 App Store Configuration

### App Store Connect Setup

1. **Create app record** with bundle ID `com.discoshadow.app`
2. **Configure subscription** with product ID `fever_dream_subscription_monthly`
3. **Set up banking** and tax information
4. **Add privacy policy** and terms of service
5. **Upload screenshots** and app metadata

### TestFlight Distribution

```bash
# Build for distribution
xcodebuild archive -project DiscoShadowApp.xcodeproj \
                  -scheme DiscoShadowApp \
                  -destination "generic/platform=iOS"

# Upload via Xcode Organizer or Transporter
```

## 🧪 Development & Testing

### Local Development

1. **Enable developer mode** on iOS device
2. **Connect device** via USB or Wi-Fi
3. **Build and run** from Xcode
4. **Test camera effects** in real-time

### Subscription Testing

1. **Sandbox Environment**
   - Create sandbox testers in App Store Connect
   - Sign out of App Store on test device
   - Test purchase flow with sandbox account

2. **TestFlight Testing**
   - Upload beta build
   - Invite external testers
   - Verify subscription functionality

### Performance Optimization

- **Metal Performance Shaders** for GPU-intensive operations
- **Texture caching** to reduce memory allocation
- **Audio buffer optimization** for real-time processing
- **Frame rate monitoring** to maintain 60fps

## 📚 Documentation

### Additional Resources

- [`SUBSCRIPTION_SETUP.md`](./SUBSCRIPTION_SETUP.md) - Complete subscription implementation guide
- [`TESTFLIGHT_STATUS.md`](./TESTFLIGHT_STATUS.md) - Current TestFlight deployment status
- [`SUBSCRIPTION_FIX_NOTES.md`](./SUBSCRIPTION_FIX_NOTES.md) - Recent subscription fixes and improvements

### API Documentation

- [Apple StoreKit](https://developer.apple.com/documentation/storekit)
- [MusicKit Documentation](https://developer.apple.com/documentation/musickit)
- [Metal Performance Shaders](https://developer.apple.com/documentation/metalperformanceshaders)

## 🏢 Project Information

### App Details
- **Name**: Fever Dream
- **Bundle ID**: `com.discoshadow.app`
- **Current Version**: 1.3
- **Team ID**: `AWLLM3Q8GW`
- **Target iOS**: 17.0+

### Repository
- **GitHub**: https://github.com/feverdreaminteractive/fever-dream-app.git
- **Branch**: `crossfader-v2`
- **License**: Proprietary

## 💼 Contact & Recruitment

**Interested in collaborating or discussing opportunities?**

I'm open to exciting projects, technical discussions, and career opportunities. Feel free to reach out:

### 📞 Get in Touch
- **Slack**: [@ryanclayton](https://join.slack.com/t/feverdream-workspace/shared_invite/zt-xyz123)
- **Email**: ryanclayton78@gmail.com
- **GitHub**: [@feverdreaminteractive](https://github.com/feverdreaminteractive)

### 🚀 What I'm Looking For
- iOS/SwiftUI development opportunities
- Metal/GPU programming projects
- Creative tech and visual effects work
- Startup environments with cutting-edge tech

*Always happy to discuss this project's technical implementation, architecture decisions, or potential collaborations!*

## 🤝 Contributing

This is a proprietary project. For questions or support:
- Create issues in the GitHub repository
- Contact the development team
- Review existing documentation

## 📄 License

© 2025 Fever Dream Interactive. All rights reserved.

---

*Built with ❤️ using SwiftUI, Metal, and lots of psychedelic inspiration*