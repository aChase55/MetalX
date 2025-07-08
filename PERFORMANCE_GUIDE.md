# MetalX Performance Profiling Guide

## Key Metrics to Monitor

### Frame Time Budget (60 FPS = 16.67ms)
```
Total Frame Time: 16.67ms
├── CPU Time: max 8ms
│   ├── Layer Management: < 1ms
│   ├── Effect Setup: < 2ms
│   ├── Command Building: < 1ms
│   └── Other CPU Work: < 4ms
└── GPU Time: max 12ms
    ├── Vertex Processing: < 1ms
    ├── Fragment Processing: < 8ms
    ├── Compute Shaders: < 2ms
    └── Bandwidth/Sync: < 1ms
```

## Profiling Checklist

### Before Each Release
- [ ] Profile on minimum spec device (iPhone 12)
- [ ] Test with maximum supported layers (target: 100)
- [ ] Verify memory stays under 500MB for typical use
- [ ] Check thermal throttling after 10 minutes use
- [ ] Validate battery drain < 20% per hour

### Instruments Templates

#### MetalX GPU Profile
1. GPU Usage
2. GPU Memory
3. Shader Profiler
4. Display (for FPS)

#### MetalX Memory Profile  
1. Allocations
2. Leaks
3. VM Tracker
4. Virtual Memory

#### MetalX System Profile
1. Time Profiler
2. System Trace
3. Thermal State
4. Energy Log

## Common Performance Issues

### Issue: Frame Drops
**Symptoms**: FPS below 60, stuttering
**Check**:
- Shader complexity (especially in fragment shaders)
- Overdraw factor (use Xcode's GPU debugger)
- Texture bandwidth (too many large textures)
- CPU-GPU sync points

### Issue: Memory Growth
**Symptoms**: Increasing memory, eventual crash
**Check**:
- Texture pool releasing properly
- Command buffer completion handlers
- Layer cache eviction
- Retain cycles in closures

### Issue: Battery Drain  
**Symptoms**: Device heats up, battery drops quickly
**Check**:
- Unnecessary render passes
- Continuous animations
- High-precision calculations when not needed
- Background processing

## Optimization Strategies

### Quick Wins
1. **Reduce Overdraw**
   - Render opaque layers front-to-back
   - Cull invisible layers
   - Use early-z rejection

2. **Texture Optimization**
   - Use mipmaps for scaled textures
   - Compress static textures (ASTC)
   - Reduce precision where possible

3. **Shader Optimization**
   - Move calculations to vertex shader
   - Use half precision for colors
   - Minimize texture samples

### Advanced Optimizations
1. **Tile-Based Rendering**
   ```metal
   // Use imageblocks for on-chip storage
   #define TILE_SIZE 32
   ```

2. **Indirect Command Buffers**
   - GPU-driven rendering
   - Reduce CPU overhead

3. **MetalFX Upscaling**
   - Render at lower resolution
   - Upscale for display

## Performance Test Suite

```swift
// MetalXTests/Performance/PerformanceTests.swift
class PerformanceTests: XCTestCase {
    func testLayerRenderingPerformance() {
        let metrics: [XCTMetric] = [
            XCTClockMetric(),        // Wall time
            XCTCPUMetric(),          // CPU usage
            XCTMemoryMetric(),       // Memory usage
            XCTStorageMetric()       // Disk I/O
        ]
        
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        
        measure(metrics: metrics, options: options) {
            // Render 50 layers with effects
            renderComplexScene()
        }
    }
}
```

## Automated Performance Regression Detection

```yaml
# .github/workflows/performance.yml
name: Performance Tests
on: [pull_request]

jobs:
  performance:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run Performance Tests
        run: |
          xcodebuild test \
            -scheme MetalXPerformanceTests \
            -destination 'platform=iOS Simulator,name=iPhone 14' \
            -enableCodeCoverage NO \
            -resultBundlePath results.xcresult
      
      - name: Compare with Baseline
        run: |
          swift run PerformanceCompare \
            --baseline main \
            --current ${{ github.sha }} \
            --threshold 5  # Allow 5% regression
```