# CircuitLens Privacy Policy

**Effective Date:** November 24, 2026

CircuitLens ("the App") is built for private, on-device electronics learning.

## Data Collection
**CircuitLens does not collect, sell, share, or transmit any personal data to external servers.**

- **Camera & LiDAR Depth:** Used strictly on-device in real time to read printed circuit board (PCB) silkscreen designators, chip markings, and physical board dimensions. Frames are processed locally using Apple Vision and ARKit and are never uploaded to third-party servers.
- **On-Device AI (Apple Intelligence):** Board explanations and Q&A run locally on your device using Apple's on-device Foundation Models framework (with a local offline fallback when Apple Intelligence is unavailable).
- **Saved Board Profiles:** Photos and board profiles you save are stored locally in the app's private Documents folder on your device.
- **Optional Local Network Sync:** If you explicitly tap "Save Teardown to pi-nas.local", the app sends the teardown JSON and photo only to the local network URL you enter.

## Contact
For support or privacy questions, contact Craig Merry at `craig@craigmerry.com` or open an issue at https://github.com/craigm26/circuit-lens.
