# Source acknowledgements

## JG-RND

RND SysEx encodings, CSV compatibility and JG firmware interaction behaviour
are adapted from [JG-RND](https://github.com/jgharding/JG-RND), by jgharding.
The adaptations include the native protocol codec, patch archive CSV handling
and device-session recall logic. These are Swift implementations; the upstream
Svelte/Electron editor is not a runtime dependency.

The MIT notice below applies to the upstream editor and original patch-code
portions. It does not cover Cyma Forma's RND firmware. No firmware binary is
included in this repository, and this project grants no rights to that firmware.

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

## xybuddy / TEBuddy

Capture design was informed by Antony Nasce's xybuddy / TEBuddy implementation:
separate monitoring gain, input meters, local takes and bounded asynchronous
file writing. rndbuddy uses its own stereo recording sink with Apple's
ExtAudioFile services; no OP-XY device protocol or capture implementation is
imported as a dependency.

## RND pixels

RND pixels is hosted by Cyma Forma at https://pixels.cymaforma.com. rndbuddy
loads that site live and retains its attribution. No site artwork, fonts or
visual-engine assets are bundled or redistributed. Official MIDI commands
are independently documented from the publicly delivered MIDI client.

## Project licence and distribution

Original rndbuddy contributions use the root [Apache 2.0 licence](../../LICENSE).
These acknowledgements preserve the applicable upstream terms; they do not
relicense the complete MIDIWeb or MIDIVision repositories or the Pixels site.
Retain the full JG-RND MIT notice with copies or substantial portions of its
code, including applicable notices shipped with application distributions.

rndbuddy is an independent companion. References to Cyma Forma, RND and Pixels
do not imply affiliation or endorsement or grant rights to their trademarks.
