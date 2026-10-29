# Source acknowledgements

## JG-RND

RND SysEx encodings, CSV compatibility and JG firmware behaviour are adapted
from https://github.com/jgharding/JG-RND. No firmware binary is included in
rndbuddy. The following licence covers the original JG editor/patch code only.

MIT License below covers the JG-RND editor source code and the original
patch code written by jgharding. It does NOT cover the RND synth firmware.

The firmware files in public/firmware/ are based on Cyma Forma's RND firmware,
which is Cyma Forma's work and belongs to them. A modified version is hosted
here for flashing your own RND only. This repository does not grant you, and
cannot grant any right to copy, redistribute or reuse that firmware.
Do not redistribute it.

MIT License

Copyright (c) 2026 jgharding

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## MIDIWeb and MIDIVision

The WebMIDI bridge follows design lessons from Antony Nasce's MIDIWeb project.
The repository-local MIDIVisionHandTrackingCore package is copied from Antony
Nasce's MIDIVision project, with a synchronous capture-queue entry point added.
These app-specific integrations do not import their full browser or UI.

## RND pixels

RND pixels is hosted by Cyma Forma at https://pixels.cymaforma.com. rndbuddy
loads that site live and retains its attribution. No site artwork, fonts or
visual-engine assets are bundled or redistributed. Official MIDI commands
are independently documented from the publicly delivered MIDI client.
