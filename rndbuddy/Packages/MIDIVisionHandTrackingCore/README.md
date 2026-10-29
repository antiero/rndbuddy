# MIDIVisionHandTrackingCore

Seed Swift package for Vision hand-joint extraction and skeleton overlay geometry.

Scope intentionally excludes:
- gesture recognition and classification
- MIDI behavior
- depth/TrueDepth processing
- UI framework-specific rendering

Main APIs:
- `VisionHandTrackingService`: Vision request wrapper producing normalized hand joint sets
- `HandSkeletonLayout`: static joint chains and palm-center helper
- `AspectFillPointMapper`: converts normalized joints into aspect-fill display space
