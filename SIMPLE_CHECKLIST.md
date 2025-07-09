# MetalX Simple Implementation Checklist

## 🎯 Goal: Working Photo Editor in 7 Days

### Day 1: Display an Image ✅
- [ ] Create `SimpleImageView.swift` - basic MTKView that shows red rectangle
- [ ] Build and verify red rectangle appears
- [ ] Add image loading - show actual image
- [ ] Build and verify image appears
- [ ] **End of Day 1: Can load and display photos**

### Day 2: Brightness Adjustment ✅
- [ ] Add brightness slider to UI
- [ ] Create shader that adjusts brightness
- [ ] Wire slider to shader parameter
- [ ] Build and test brightness changes
- [ ] **End of Day 2: Can adjust image brightness**

### Day 3: More Adjustments ✅
- [ ] Add contrast adjustment
- [ ] Add saturation adjustment  
- [ ] Stack adjustments in one shader
- [ ] Build and test all adjustments work
- [ ] **End of Day 3: Basic photo editing works**

### Day 4: Save Edited Images ✅
- [ ] Add save button
- [ ] Render to texture instead of screen
- [ ] Convert texture to UIImage
- [ ] Save to photo library
- [ ] **End of Day 4: Can save edited photos**

### Day 5: Image Picker ✅
- [ ] Add photo picker button
- [ ] Load images from photo library
- [ ] Handle different image sizes
- [ ] Test with various photos
- [ ] **End of Day 5: Complete basic photo editor**

### Day 6: First Real Effect ✅
- [ ] Implement gaussian blur
- [ ] Add blur amount slider
- [ ] Make it work with other adjustments
- [ ] **End of Day 6: Have one "pro" effect**

### Day 7: Polish & Ship ✅
- [ ] Add app icon
- [ ] Improve UI layout
- [ ] Add reset button
- [ ] Test on real device
- [ ] **End of Day 7: Shippable photo editor!**

## 🛑 Build Validation Rules

**BEFORE marking any checkbox:**
1. Run `xcodebuild` or build in Xcode
2. Run the app in simulator
3. Test the new feature works
4. See visible results on screen

**If build fails:** 
- STOP
- Fix errors
- Don't proceed until green

## 🚫 NOT in First Week

- ❌ Layers
- ❌ Video
- ❌ Complex architecture  
- ❌ Optimization
- ❌ Error handling
- ❌ Memory management
- ❌ Fancy UI
- ❌ Multiple effects at once

## 📱 What Success Looks Like

By end of Week 1, you have an app that:
1. Opens photos from library
2. Adjusts brightness/contrast/saturation
3. Applies blur
4. Saves edited photos
5. **Actually works and doesn't crash**

## 🔧 If Something Doesn't Work

1. **Shader won't compile?** 
   - Start with pass-through shader
   - Add one line at a time

2. **Image won't display?**
   - First get a colored rectangle
   - Then try a hardcoded image
   - Then load from library

3. **Crashes on device?**
   - Test each feature in isolation
   - Use print statements liberally
   - Check if device is nil

## 📝 Daily Status Format

End each day with:
```
Day X Complete:
- ✅ What works: [specific features]
- 🏗 What's in progress: [specific files/functions]  
- ❌ What's broken: [specific errors]
- 📱 Screenshot of current app state
```

## Week 2 and Beyond

Only after Week 1 is 100% working:
- Add more effects
- Implement layers
- Add undo/redo
- Improve architecture
- Consider video

**Remember: Working code > Perfect code**