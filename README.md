# ThoughtNote

A native iOS app that lets you **ramble by voice** (e.g., while driving), then turns it into **concise personal notes**: summaries, bullet points, and actionable to-dos.

## Features

### Core Features (MVP)
- **One-tap voice recording** - Start capturing thoughts with a single tap or hands-free via Siri
- **Real-time transcription** - Uses Apple's Speech framework for accurate speech-to-text
- **AI-powered summarization** - Converts transcripts into structured notes:
  - Concise summary
  - Key bullet points
  - Actionable to-dos with priorities
- **Session management** - Append to existing thoughts with "add to that thought"
- **Search & browse** - Find thoughts by text, filter by mode

### Recording Modes
1. **Ramble On** - Continuous capture until you stop; great for brainstorming
2. **Guided Thinking** - App asks follow-up questions to help develop ideas
3. **Decision Helper** - Weigh pros/cons and get structured recommendations

### Driving-Friendly Design
- Large, easy-to-tap buttons
- Audio doesn't interrupt navigation or music
- Works with screen locked (background audio)
- Minimal UI while recording

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Setup

1. Clone the repository
2. Open `ThoughtNote.xcodeproj` in Xcode
3. Set your development team in Signing & Capabilities
4. Build and run on a device (microphone required)

## Permissions

The app requires:
- **Microphone** - For recording voice thoughts
- **Speech Recognition** - For transcribing voice to text

## Architecture

```
ThoughtNote/
├── App/
│   └── ThoughtNoteApp.swift         # App entry point
├── Models/
│   ├── Thought.swift                # Main thought entity (SwiftData)
│   ├── TodoItem.swift               # To-do item entity
│   └── SummarizerOutput.swift       # LLM response structure
├── Services/
│   ├── AudioRecording/
│   │   └── AudioRecordingService.swift
│   ├── SpeechTranscription/
│   │   └── SpeechTranscriptionService.swift
│   └── Summarization/
│       ├── SummarizerProtocol.swift  # Pluggable interface
│       ├── StubSummarizer.swift      # Mock for testing
│       └── RemoteSummarizer.swift    # API-based implementation
├── Views/
│   ├── Home/
│   │   └── HomeView.swift
│   ├── Record/
│   │   └── RecordView.swift
│   ├── ThoughtDetail/
│   │   └── ThoughtDetailView.swift
│   └── Settings/
│       └── SettingsView.swift
├── Intents/
│   └── ThoughtIntents.swift         # Siri Shortcuts
└── Resources/
    └── Assets.xcassets/
```

## Siri Shortcuts

The app supports these voice commands:
- "New thought in ThoughtNote"
- "Add to my latest thought in ThoughtNote"
- "Help me decide in ThoughtNote"

## Configuration

### Summarizer Options

1. **Stub (Default)** - Mock responses for development/testing
2. **Remote API** - Connect to OpenAI, Anthropic, or compatible API
3. **On-Device** - Coming soon: local llama.cpp integration

Configure in Settings > Summarizer.

## Data Storage

- All thoughts stored locally using SwiftData
- Audio files optionally saved (configurable in Settings)
- No cloud sync required (optional iCloud sync planned)

## Privacy

- Audio processed locally when possible
- No analytics or tracking
- Your thoughts remain on your device
- Optional remote API for summarization (configurable)

## License

MIT License

## Contributing

Contributions welcome! Please read the contributing guidelines first.
