# Open Vibrance

**Quick minimalistic transcription overlay**

![Placeholder for GIF/Screenshot](paste images)

Open Vibrance is a simple desktop overlay that transcribes the speech. Hit a shortcut, speak out, and turn you words into text—copied to the clipboard and pasted right into the app you're currently using. 
Currently is is using
- *Elevenlabs* scribe model
- _*TODO*_ - *OpenAI* whisper

## Ideal for
- 🎧 **Vibe coding** – Turn your thoughts into coding prompts
- 🚀 **Prompt crafting** – Speak out your prompts on-the-fly
- 💬 **Messaging** – Quickly reply to messages
- 📝 **Note-taking** – Keep the flow state while taking the notes

## Main Features
- 💰 **Free** (kind of): no subscriptions or limits in the app, works with your own API key
- 🎙️ **Easy-to-use:** Start and stop recording with a single keystroke
- ⚡ **Precise transcription:** Uses lates and greatest Elevenlabs model
- 📋 **Automatic text paste:** Transcribed note instantly appears in your active app and is also copied to your clipboard. 
- 📌 **Minimal UI:** Just one simple overlay indicator dot that stays on top and can be moved around
- 🌐 **Cross-platform:** Built with Flutter, Open Vibrance runs smoothly on Windows, macOS, and Linux (at least i hope so, tested only on windows 😅)

## How to use
1. Make Elevenlabs account and create API key (you will have to get cheapers subscription)
2. Click the dot indicator and paste API key
3. **Press the hotkey (`Alt+Q`)** to start recording. Release the keys when done speaking
4. **Done!** Your transcription appears in your active app and is copied to your clipboard.

## How to set up
- **For developers (building from source):**
    - Make sure you have Flutter installed.
    - Clone this repository and run `flutter pub get`.
    - Launch the app with the command: `flutter run windows` (replace `windows` with your platform: `macos` or `linux`).