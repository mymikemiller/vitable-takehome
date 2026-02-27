# Vitable Health — Scheduling Assistant

A full-stack virtual scheduling assistant that guides patients through booking a healthcare appointment via a conversational interface. The backend is powered by Claude and enforces a structured intake flow; the frontend is a cross-platform Flutter application with a production-grade chat UX.

---

## Live Demo

| Service | URL |
|---|---|
| Frontend | https://vitable-takehome.onrender.com |
| Backend | https://vitable-takehome-backend.onrender.com |

Both services are deployed on Render's free tier. After a period of inactivity, they spin down and require 30–60 seconds to restart on the next request. If the first chat message returns an error, wait a few seconds and try again — the backend will be ready.

---

## Project Overview

The assistant collects six required fields through natural conversation — name, contact information, reason for visit, visit category, preferred date, and preferred time — then presents a summary for confirmation before booking. No appointment is created until the patient explicitly confirms.

Key characteristics:

- **Server-side session state.** The backend owns the full conversation history and all collected fields. The client sends only the current message and receives only the assistant's reply.
- **Structured Claude output.** Every Claude response is a validated JSON object containing the assistant message and the current state of all intake fields. This makes the backend deterministic and easy to test.
- **One message per turn.** The backend enforces a strict single-message contract. Claude is instructed to ask exactly one question per turn and never produce multiple assistant messages from a single request.
- **Client-driven typing simulation.** The frontend implements a realistic AI typing experience with a reading delay, animated three-dot indicator, and character-by-character text reveal — independent of the backend.
- **Calendar integration.** After a confirmed booking, the backend returns a structured calendar event. The frontend generates a Google Calendar URL and a standards-compliant `.ics` file for Apple Calendar.

---

## Architecture

### Backend (`/backend`)

Built with FastAPI and the Anthropic Python SDK.

- **Model:** `claude-sonnet-4-6`
- **Prompting strategy:** Structured JSON output. The system prompt instructs Claude to always return a fixed JSON schema containing the assistant message and extracted field values. The backend validates this with Pydantic on every turn, which prevents schema drift and makes field extraction reliable without tool use.
- **Session state:** Stored in-memory as a dict of `ConversationState` objects keyed by session ID. Identity fields (name, contact) are retained across bookings; scheduling fields are cleared after each confirmation so the patient can book a second appointment without re-introducing themselves.
- **Timezone handling:** The client sends its UTC offset (in signed minutes) with every request. The backend uses this to compute "today's date" for the system prompt, interpret collected appointment times as the patient's local time, and format the confirmation message correctly — ensuring correctness when the server and user are in different timezones.
- **Booking guards:** Past-date rejection, 60-minute conflict detection, and a missing-field check all run before the appointment is committed.
- **Two-step confirmation:** Claude signals `confirm_ready` when all fields are collected, then `book_now` only after the patient explicitly confirms. The booking logic runs exclusively in the backend on `book_now`.

### Frontend (`/frontend`)

A single Flutter codebase targeting iOS, Android, and Web.

- **State management:** [Signals](https://pub.dev/packages/signals_flutter) (`signals_flutter ^6.2`). All state lives in `ChatController`, instantiated once in `main.dart` and injected via constructors. No `setState`, no Provider, no Riverpod.
- **Architecture:** Three strict layers — `ChatApiService` (stateless Dio client), `ChatController` (signals + business logic), and UI widgets (zero networking or business logic).
- **Typing simulation:** When the user sends a message, a 650ms reading delay and a network request fire in parallel. If the response arrives before 650ms, the typing indicator is skipped entirely and character animation begins immediately. If not, the three-dot indicator appears until the response is ready.
- **Performance:** Per-character rebuilds are scoped to a single `Watch` widget inside the animating message bubble. The `ListView`, `Scaffold`, and all other bubbles do not rebuild during animation.
- **Web layout:** On wide screens, the chat column is centered in a dark outer background with a maximum width of 860px. On mobile, the layout is edge-to-edge with safe area insets.

---

## Running the Backend Locally

### Install Python with uv

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uv python install
```

### Set up the environment

```bash
cd backend
uv venv
uv pip install -r requirements.txt
```

### Run

```bash
ANTHROPIC_API_KEY=your_key_here uv run uvicorn main:app --reload
```

The backend will be available at `http://localhost:8000`.

---

## Testing the Backend Manually

```bash
curl -s -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -d '{"session_id": "test-001", "message": "I have a persistent cough", "utc_offset_minutes": -300}'
```

The response will contain an `assistant_message` with Claude's next intake question and a `calendar_event` field (null until booking is confirmed). Subsequent requests with the same `session_id` continue the conversation.

---

## Running the Frontend Locally

Update the base URL in `frontend/lib/main.dart` before running:

```dart
baseUrl: 'http://localhost:8000',  // was: https://vitable-takehome-backend.onrender.com
```

### Web

```bash
cd frontend
flutter pub get
flutter run -d chrome
```

### iOS

```bash
flutter run -d ios
```

Requires Xcode and either a connected device or a running simulator.

### Android

```bash
flutter run -d android
```

Requires Android Studio and either a connected device or a running emulator.

---

## Design Decisions

**Structured JSON output over tool use.** Tool use is well-suited for triggering discrete side effects. Here, the primary goal is reliable field extraction across every turn. A fixed JSON schema enforced by Pydantic on every response makes the extraction logic simple, testable, and transparent without the overhead of a tool-call round-trip.

**Server-side session state.** Keeping history and collected fields on the server simplifies the client significantly — it sends one message and receives one reply. It also means the client cannot tamper with or corrupt intake state, and the server can enforce booking invariants (past-date rejection, conflict detection) authoritatively.

**One message per turn.** Allowing the client to send multiple messages before receiving a response would require queuing, ordering guarantees, and more complex conflict detection. A strict one-in/one-out contract keeps both sides simple and correct.

**No streaming.** Streaming would allow the response to begin rendering before the full message is received, but it would require the client to buffer a partial JSON object before parsing it. Given that the backend response is a structured JSON payload rather than prose, streaming adds complexity for limited UX benefit. The typing simulation on the frontend provides the perception of a live response without it.

**Client-driven typing simulation.** Decoupling the animation from the network response gives the frontend full control over timing and feel. The 650ms reading delay before showing the typing indicator prevents a flash of the indicator on fast connections, while the character animation on arrival makes responses feel considered rather than instant.

**Signals over Bloc/Riverpod.** Signals offer fine-grained reactive updates with minimal boilerplate. The key property for this application is that a `Watch` widget subscribes only to the signals it reads — so the animating text widget rebuilds per character while the rest of the widget tree stays completely static. This is difficult to achieve cleanly with stream-based approaches without explicit `StreamBuilder` scoping.

---

## Render Deployment Notes

The backend is deployed as a Render **Web Service** running `uvicorn main:app --host 0.0.0.0 --port $PORT`. The `ANTHROPIC_API_KEY` environment variable is set in the Render dashboard.

The frontend is deployed as a Render **Static Site** built with `flutter build web --release`. The build output directory is `build/web`.

Both services are on the free tier, which suspends instances after 15 minutes of inactivity. The first request after a cold start may take 30–60 seconds. This is a deployment constraint, not an application issue.
