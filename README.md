# Cuemera
```markdown
# Cuemera

**Did your girlfriend dump you because you can't take a decent photo?**
**Does your own family cringe at your photos in the group chat?**
**Even your cat is embarrassed to be seen in frame with you?**
**Your last 200 camera roll photos are all the same awkward half-smile against a wall?**

Cuemera doesn't teach you to pose. It directs you — like a real fashion photographer standing next to you.

> People don't need more poses. People need direction.

## The Problem

Pose-copying apps hand you a static reference image and ask you to contort yourself into matching it. That's not direction — it's mimicry, and it falls apart the moment your body, your lighting, or your context doesn't match the reference. A real photographer doesn't do that. They watch you, read the moment, and tell you exactly what to adjust, right now, in your own words.

Cuemera follows that model instead:

**Goal → Understand → Observe → Direct → Capture → Review → Improve**

not:

~~Pose → Copy → Capture~~

## Features

- **Goal Selection** — pick a photography intent (editorial, LinkedIn, travel, dating, beach, luxury) and Cuemera tailors every decision that follows to it.
- **Real-time Scene Analysis** — on-device pose, face, and lighting understanding, continuously updated as you move.
- **Voice Director** — a single, prioritized spoken instruction at any moment, chosen from everything happening in the frame right now.
- **Target Zone + Auto Capture** — a live visual target that fills in as your pose aligns, triggering an automatic capture when you're ready (with manual capture always available as a fallback).
- **Editorial Score** — every shot is scored across composition, lighting, expression, background, and story, weighted to your chosen goal.
- **Album Director** — tracks shot diversity across a session and suggests what to shoot next so your album doesn't end up as twenty near-identical photos.

## Architecture

Cuemera is built as an 11-layer AI pipeline, running entirely as on-device edge AI in Flutter — no cloud round-trip for the core photography loop:

1. Goal Understanding
2. Human Understanding
3. Scene Understanding
4. Editorial Brain
5. Photographer Brain
6. Direction Engine
7. Tracking Engine
8. Capture Engine
9. Quality Engine
10. Album Director
11. Memory Layer

**Tech stack**: Flutter, Riverpod (state management), `google_mlkit_*` (pose/face/selfie segmentation), `flutter_tts` (voice direction), Hive (local persistence).

For a full breakdown of every layer, its files, data flow, and current implementation status, see **[PROJECT_STATUS.md](./PROJECT_STATUS.md)** — this README intentionally does not duplicate that detail.

## Getting Started

### Prerequisites

- Flutter SDK `^3.8.1` (Dart 3.8+)
- Android: minSdk 21+
- iOS: 13.0+
- A physical device is strongly recommended — camera + ML Kit inference does not reflect real performance in a simulator/emulator.

### Setup

```bash
git clone <repository-url>
cd cuemera
flutter pub get
flutter run
```

Cuemera requests **camera** and **microphone** permissions on first launch — both are required for the core experience (scene analysis and voice direction) and must be granted for the app to proceed past the splash screen.

## Project Structure

```
core/       shared app-wide constants, theming, and services (camera, ML Kit, TTS, memory, DI)
features/   feature-first modules, one per pipeline layer/screen (goal_selection, scene_analysis, voice_director, capture, editorial_score, album, camera_session, splash)
shared/     reusable UI widgets and models used across multiple features
```

## Current Status

Cuemera's core end-to-end loop — goal selection through capture, scoring, and album review — is implemented and wired together on top of Riverpod-managed state. Real-device validation (performance, battery, permission flow under real conditions) has not yet been performed, and a few architectural areas (rule content depth, memory-driven personalization) are still early. See **[PROJECT_STATUS.md](./PROJECT_STATUS.md)** for exact completion percentages, a full layer-by-layer breakdown, and the current list of known gaps.

## Color Palette (Dark Theme)

| Token | Hex |
|---|---|
| background | `#14141A` |
| surface | `#232329` |
| text | `#F3F1EA` |
| textMuted | `#9B978C` |
| accent | `#C9A227` |
| targetZone | `#5ED1C9` |
| success | `#7FA65C` |
| warning | `#E0A458` |

## License

This project is currently unlicensed for public distribution. All rights reserved unless otherwise stated.

## Contributing

Contributions, issues, and feature suggestions are welcome. Please open an issue to discuss significant changes before submitting a pull request.
```
