# MetalX Xcode Project Guide

## 🎯 Using the Existing Xcode Project

The Xcode project already exists at:
```
/Users/alexchase/Developer/MetalX/MetalX.xcodeproj
```

**DO NOT** create a new project. Use this one!

## Adding Files to the Project

### Method 1: Via Xcode (Recommended)
1. Open `MetalX.xcodeproj` in Xcode
2. Right-click on the appropriate group (e.g., "MetalX" for framework code)
3. Select "New File..."
4. Choose file type (Swift File, Metal File, etc.)
5. **IMPORTANT**: Check the correct target:
   - ✅ MetalX (for framework code)
   - ✅ MetalXDemo (for demo app code)

### Method 2: Via Finder + Xcode
1. Create file in Finder at correct location
2. In Xcode, right-click the group
3. "Add Files to MetalX..."
4. Select your file
5. **IMPORTANT**: Check "Copy items if needed" and select correct target

## Project Structure in Xcode

```
MetalX.xcodeproj
├── MetalX/                    # Framework target
│   ├── Info.plist
│   ├── MetalX.h              # Umbrella header
│   └── [Your framework code goes here]
├── MetalXDemo/                # Demo app target  
│   ├── Info.plist
│   ├── MetalXDemoApp.swift   # App entry point
│   ├── ContentView.swift     # Main view
│   └── [Your demo code goes here]
└── MetalXTests/               # Test target
```

## Build & Run Commands

### Command Line Build
```bash
cd /Users/alexchase/Developer/MetalX

# Build framework only
xcodebuild -scheme MetalX -destination 'platform=iOS Simulator,name=iPhone 15' build

# Build and run demo app
xcodebuild -scheme MetalXDemo -destination 'platform=iOS Simulator,name=iPhone 15' build
xcrun simctl launch booted com.yourcompany.MetalXDemo
```

### Verify Build Works
```bash
# This should complete without errors
xcodebuild -list -project MetalX.xcodeproj
```

## Common Xcode Issues

### "No such module 'MetalX'"
In MetalXDemo files, add:
```swift
import MetalX  // Import the framework
```

### "Use of unresolved identifier"
1. Check file is added to correct target
2. Check access modifiers (`public` for framework APIs)
3. Clean build folder: Cmd+Shift+K

### Metal Shader Compilation
1. `.metal` files must be added to MetalX target
2. Set "Metal Compiler - Build Options" → "Language Version" to "Metal 3.0"
3. Shaders compile during build, check for errors

## Framework vs App Code

### Framework Code (MetalX target)
- All rendering code
- Effects and filters
- Must mark public APIs as `public`
- Example:
```swift
// In MetalX/Core/SimpleImageView.swift
public struct SimpleImageView: UIViewRepresentable {
    public init(image: UIImage) {
        // ...
    }
}
```

### App Code (MetalXDemo target)
- UI and user interaction
- Uses the framework
- Example:
```swift
// In MetalXDemo/ContentView.swift
import SwiftUI
import MetalX  // Import our framework

struct ContentView: View {
    var body: some View {
        SimpleImageView(image: UIImage(named: "sample")!)
    }
}
```

## Build Settings to Check

### MetalX (Framework) Target
- Deployment Target: iOS 16.0
- Build Active Architecture Only: Yes (Debug)
- Enable Bitcode: No
- Metal Language Version: Metal 3.0

### MetalXDemo (App) Target  
- Deployment Target: iOS 16.0
- Embedded Binaries: Must include MetalX.framework

## Testing Your Setup

1. **Test 1: Framework Builds**
```bash
xcodebuild -scheme MetalX build
# Should succeed with no errors
```

2. **Test 2: Demo App Builds**
```bash
xcodebuild -scheme MetalXDemo build  
# Should succeed with no errors
```

3. **Test 3: Import Works**
Create a test file in MetalXDemo:
```swift
import MetalX
// If this doesn't error, framework is properly linked
```

## Debugging Build Issues

### Enable Verbose Output
```bash
xcodebuild -scheme MetalX build -verbose
```

### Clean Everything
```bash
xcodebuild clean
rm -rf ~/Library/Developer/Xcode/DerivedData/MetalX-*
```

### Check Target Membership
In Xcode, select a file and check right panel:
- ✅ Target Membership should be checked for appropriate target

## Remember

1. **ALWAYS** build after adding files
2. **ALWAYS** use the existing project
3. **ALWAYS** check target membership
4. **ALWAYS** mark framework APIs as `public`
5. **NEVER** create a new Xcode project

The project is already set up correctly - just add your code!