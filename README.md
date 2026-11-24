# CircuitLens — AR Electronics Explorer for Family Learning (`pi-nas.local`)

Point your iPhone at any circuit board to read silkscreen reference designators (`C3`, `IC5`, `RY2`, `R12`) and laser-etched IC markings (`MIP290`, `LM7805`, `RP2350`) in live AR, understand what the **whole electronic device** does using on-device **Apple Intelligence (`FoundationModels`)**, ask follow-up questions at **Kid (10) / Teen / Engineer** depth, and save teardowns straight to your family `pi-nas.local` electronics studio.

## Features
- **Live AR Silkscreen Scanner (`Vision` + `AVFoundation`):** Floating color-coded callout pills pinned to detected components.
- **Freeze & Explore Macro Mode:** Snap a crisp macro frame, tap any component hotspot, and see an instant family safety banner when mains/high-voltage clues (`RY`, `F`, `MOV`, `MIP290`) appear.
- **On-Device Apple Intelligence (`FoundationModels`):** `@Generable` whole-board summary, power/signal flow, and interactive Q&A (100% offline, zero API keys, with deterministic offline fallback).
- **Family Studio Sync (`pi-nas.local:8088`):** Run `python3 pi-nas-studio/server.py` on `pi-nas.local` to archive every scanned board into a browsable web gallery.

## Build & Upload (MacInCloud)
```bash
cd ios
KEYCHAIN_PASSWORD=... ./scripts/archive_upload.sh 68T2S87K39 0803ec59-b64d-4014-9519-d5e8c7079f0c
```
