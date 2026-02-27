"""
main.py — Vitable Health Virtual Scheduling Assistant

FastAPI backend powered by Anthropic claude-sonnet-4-6.
Implements a two-step conversational appointment booking flow with:
  - In-memory session state
  - Structured JSON responses from Claude
  - Emergency detection and short-circuit
  - Conflict detection for overlapping appointments
  - Turn discipline: exactly one assistant message per request
"""

import json
import uuid
import random
import logging
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional

from anthropic import Anthropic
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────────────────────────────────────
# APP + ANTHROPIC CLIENT
# ─────────────────────────────────────────────────────────────────────────────
app = FastAPI(title="Vitable Health Scheduling Assistant")

from fastapi.middleware.cors import CORSMiddleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Reads ANTHROPIC_API_KEY from environment automatically.
client = Anthropic()

# ─────────────────────────────────────────────────────────────────────────────
# IN-MEMORY STATE STORE
# Both dicts reset on server restart — intentional per spec.
#   sessions: per-session conversation + collected field state
#   scheduled_appointments: list of confirmed bookings per session
# ─────────────────────────────────────────────────────────────────────────────
sessions: Dict[str, "ConversationState"] = {}
scheduled_appointments: Dict[str, List["ScheduledAppointment"]] = {}


# ─────────────────────────────────────────────────────────────────────────────
# PYDANTIC MODELS
# ─────────────────────────────────────────────────────────────────────────────

class ChatRequest(BaseModel):
    """Inbound request from client."""
    session_id: str = Field(..., description="UUID generated and persisted by the client")
    message: str = Field(..., description="User's message text")


class CalendarEvent(BaseModel):
    """Backend-generated calendar event returned after a successful booking."""
    title: str
    start_iso: str   # ISO 8601 UTC datetime
    end_iso: str     # ISO 8601 UTC datetime
    description: str
    location: Optional[str] = None


class ChatResponse(BaseModel):
    """Outbound response to client."""
    assistant_message: str
    calendar_event: Optional[CalendarEvent] = None


class ConversationState(BaseModel):
    """
    Mutable per-session state.

    Identity fields (full_name, contact_info) are RETAINED across appointments
    so the user does not need to re-introduce themselves for a second booking.

    Scheduling fields (reason_for_visit through book_now) are CLEARED after
    each successful booking to allow a fresh intake for the next appointment.
    """
    # Conversation history forwarded to Claude on every turn.
    history: List[Dict[str, str]] = Field(default_factory=list)

    # Identity — retained across bookings.
    full_name: Optional[str] = None
    contact_info: Optional[str] = None

    # Scheduling — cleared after each successful booking.
    reason_for_visit: Optional[str] = None
    visit_category: Optional[str] = None
    preferred_date: Optional[str] = None    # YYYY-MM-DD
    preferred_time: Optional[str] = None    # HH:MM (24-hour)
    confirm_ready: bool = False
    book_now: bool = False


class ClaudeStructuredResponse(BaseModel):
    """
    Strict Pydantic model that maps to Claude's required JSON output schema.
    Every field must be present in every Claude response; Pydantic validates this.
    """
    assistant_message: str
    full_name: Optional[str] = None
    reason_for_visit: Optional[str] = None
    visit_category: Optional[str] = None
    preferred_date: Optional[str] = None    # YYYY-MM-DD or null
    preferred_time: Optional[str] = None    # HH:MM or null
    contact_info: Optional[str] = None
    confirm_ready: bool = False
    book_now: bool = False
    is_emergency: bool = False


class ScheduledAppointment(BaseModel):
    """A confirmed appointment persisted in the in-memory store."""
    appointment_id: str
    session_id: str
    full_name: str
    contact_info: str
    reason_for_visit: str
    visit_category: str
    start_dt: datetime   # UTC-aware
    end_dt: datetime     # UTC-aware (start + 60 min)


# ─────────────────────────────────────────────────────────────────────────────
# SCHEDULE APPOINTMENT STUB
# Simulates a call to an external scheduling/EHR API.
# In production: replace body with async HTTP call, database write, etc.
# Returns a short numeric appointment ID for display to the patient.
# ─────────────────────────────────────────────────────────────────────────────
def schedule_appointment(
    session_id: str,
    full_name: str,
    contact_info: str,
    reason_for_visit: str,
    visit_category: str,
    start_dt: datetime,
) -> str:
    """
    Stub for external scheduling API.
    Generates a 5-digit numeric appointment ID.
    """
    appointment_id = str(random.randint(10000, 99999))
    logger.info(
        "schedule_appointment | id=%s session=%s name=%s start=%s",
        appointment_id, session_id, full_name, start_dt.isoformat(),
    )
    return appointment_id


# ─────────────────────────────────────────────────────────────────────────────
# CONFLICT DETECTION
# Prevents overlapping 60-minute windows within the same session.
# Uses half-open interval logic: [start, end) overlap iff start_a < end_b AND end_a > start_b
# ─────────────────────────────────────────────────────────────────────────────
def has_conflict(session_id: str, start_dt: datetime) -> bool:
    """
    Returns True if proposed start_dt overlaps any existing appointment
    in this session.  All datetimes are UTC-aware.
    """
    proposed_end = start_dt + timedelta(hours=1)
    for appt in scheduled_appointments.get(session_id, []):
        if start_dt < appt.end_dt and proposed_end > appt.start_dt:
            return True
    return False


# ─────────────────────────────────────────────────────────────────────────────
# DATETIME PARSER
# Interprets collected date/time as LOCAL server time (same timezone as the
# user), then converts to UTC for storage and comparison.  Using replace(utc)
# directly would treat "3:00 PM" as 3 PM UTC, causing past-date false-positives
# for users in negative-offset timezones.
# ─────────────────────────────────────────────────────────────────────────────
def parse_appointment_datetime(date_str: str, time_str: str) -> datetime:
    """
    Parses "YYYY-MM-DD" + "HH:MM" as local server time and returns a
    UTC-aware datetime.  Raises ValueError on malformed input.
    """
    dt_naive = datetime.strptime(f"{date_str} {time_str}", "%Y-%m-%d %H:%M")
    # Attach the server's local timezone (mirrors the user's clock when running locally).
    local_tz = datetime.now().astimezone().tzinfo
    dt_local = dt_naive.replace(tzinfo=local_tz)
    return dt_local.astimezone(timezone.utc)


# ─────────────────────────────────────────────────────────────────────────────
# SYSTEM PROMPT BUILDER
# Embeds current session state and today's server date so Claude knows exactly
# which fields have already been collected and which still need to be asked.
# ─────────────────────────────────────────────────────────────────────────────
def build_system_prompt(state: ConversationState) -> str:
    # Use local server time so "today" matches the user's clock, not UTC.
    now_local = datetime.now().astimezone()
    today = now_local.strftime("%Y-%m-%d")
    day_of_week = now_local.strftime("%A")
    tomorrow = (now_local + timedelta(days=1)).strftime("%Y-%m-%d")

    # Snapshot of already-collected fields to prevent Claude re-asking them.
    known_fields = {
        "full_name":        state.full_name or "unknown",
        "contact_info":     state.contact_info or "unknown",
        "reason_for_visit": state.reason_for_visit or "unknown",
        "visit_category":   state.visit_category or "unknown",
        "preferred_date":   state.preferred_date or "unknown",
        "preferred_time":   state.preferred_time or "unknown",
    }

    return f"""You are a professional virtual scheduling assistant for Vitable Health.

TODAY'S DATE: {today} ({day_of_week}). Use this as the authoritative ground truth for all date calculations.

CURRENT SESSION STATE — do NOT re-ask fields that are already filled in:
{json.dumps(known_fields, indent=2)}

YOUR TASK:
Collect all required scheduling information through natural, professional conversation.
Ask only for fields currently listed as "unknown". Never re-ask a field that is already filled.

REQUIRED FIELDS:
  - full_name
  - contact_info (phone number or email address)
  - reason_for_visit
  - visit_category  (e.g., General Consultation, Follow-up, Urgent Care, Mental Health, Preventive Care)
  - preferred_date  (output as YYYY-MM-DD)
  - preferred_time  (output as HH:MM in 24-hour format)

DATE RESOLUTION RULES (relative to today = {today}):
  - "tomorrow"     → {tomorrow}
  - "next Monday"  → the first Monday strictly after today
  - "this Friday"  → the upcoming Friday if it has not already passed this week
  - Never produce a date in the past.
  - If the patient says "morning" without specifying a time, ask for a specific time.
  - When any date/time expression is ambiguous, ask for clarification rather than guessing.

DATE AND TIME DISPLAY FORMAT (applies to all text in assistant_message):
  - Dates must always be displayed as "Month Day, Year"  — e.g. "February 27, 2026", never "2026-02-27".
  - Times must always be displayed in 12-hour format with AM/PM — e.g. "3:00 PM" or "9:00 AM", never "15:00" or "09:00".
  - The preferred_date and preferred_time JSON fields must still use machine formats (YYYY-MM-DD / HH:MM).
    Only the human-readable display in assistant_message should use the friendly format above.

TWO-STEP BOOKING PROCESS:

  STEP 1 — Intake: Collect all six required fields above.
    When ALL six are known, set:
      confirm_ready = true
      book_now      = false
    And generate assistant_message summarising the appointment details, for example:
      "Here's what I have:
       - Name: Jane Doe
       - Visit: Follow-up
       - Date: March 5, 2026
       - Time: 2:00 PM
       - Contact: jane@example.com
      Shall I go ahead and book this for you?"

  STEP 2 — Confirmation: Only when the patient explicitly says yes / confirms / book it.
    Set:
      book_now          = true
      assistant_message = ""   ← empty string; the backend generates the confirmation

EMERGENCY PROTOCOL:
  If the patient describes symptoms that may be life-threatening or require immediate care:
    - Set is_emergency  = true
    - Set confirm_ready = false
    - Set book_now      = false
    - In assistant_message: instruct them to call 911 or go to the nearest emergency room immediately.
    - Do NOT proceed with scheduling.

TONE AND STYLE:
  - Professional, warm, and concise.
  - No emojis.
  - No medical advice or diagnoses.
  - Ask only one question per message.

YOU MUST ALWAYS RESPOND WITH EXACTLY THIS JSON OBJECT — no preamble, no markdown fences, no trailing text:
{{
  "assistant_message": "string",
  "full_name": "string or null",
  "reason_for_visit": "string or null",
  "visit_category": "string or null",
  "preferred_date": "YYYY-MM-DD or null",
  "preferred_time": "HH:MM or null",
  "contact_info": "string or null",
  "confirm_ready": true or false,
  "book_now": true or false,
  "is_emergency": true or false
}}"""


# ─────────────────────────────────────────────────────────────────────────────
# POST /chat — MAIN ENDPOINT
# ─────────────────────────────────────────────────────────────────────────────
@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest) -> ChatResponse:
    session_id = request.session_id

    # ── 1. Retrieve or initialise session state ──────────────────────────────
    if session_id not in sessions:
        sessions[session_id] = ConversationState()
        scheduled_appointments[session_id] = []
        logger.info("New session initialised: %s", session_id)

    state = sessions[session_id]

    # ── 2. Append user turn to conversation history ──────────────────────────
    state.history.append({"role": "user", "content": request.message})

    # ── 3. Build system prompt embedding current state + today's date ────────
    system_prompt = build_system_prompt(state)

    # ── 4. Call Anthropic API — structured prompting, no streaming ──────────
    try:
        response = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=1024,
            system=system_prompt,
            messages=state.history,
        )
    except Exception as exc:
        logger.error("Anthropic API error: %s", exc)
        raise HTTPException(status_code=502, detail="Upstream AI service unavailable")

    raw_content = response.content[0].text.strip()
    logger.info("Claude raw response [session=%s]: %s", session_id, raw_content)

    # ── 5. Parse and validate Claude's JSON response ─────────────────────────
    # Claude is instructed to return only a JSON object.  We validate the
    # structure strictly via Pydantic to catch any schema drift early.
    try:
        parsed_json = json.loads(raw_content)
        claude_resp = ClaudeStructuredResponse(**parsed_json)
    except (json.JSONDecodeError, ValueError) as exc:
        logger.error(
            "Claude returned invalid JSON [session=%s]: %s | raw: %s",
            session_id, exc, raw_content,
        )
        # Safe fallback — session state is unchanged so the user can retry.
        return ChatResponse(
            assistant_message=(
                "I'm sorry, I had trouble processing that. Could you please try again?"
            ),
            calendar_event=None,
        )

    # ── 6. Append Claude's response to conversation history ──────────────────
    # Store the raw text so future turns receive a coherent dialogue context.
    state.history.append({"role": "assistant", "content": raw_content})

    # ── 7. Merge Claude's extracted fields into session state ────────────────
    # Only overwrite a field when Claude returned a non-null, non-empty value,
    # preventing accidental erasure of previously collected information.
    if claude_resp.full_name:
        state.full_name = claude_resp.full_name
    if claude_resp.contact_info:
        state.contact_info = claude_resp.contact_info
    if claude_resp.reason_for_visit:
        state.reason_for_visit = claude_resp.reason_for_visit
    if claude_resp.visit_category:
        state.visit_category = claude_resp.visit_category
    if claude_resp.preferred_date:
        state.preferred_date = claude_resp.preferred_date
    if claude_resp.preferred_time:
        state.preferred_time = claude_resp.preferred_time

    state.confirm_ready = claude_resp.confirm_ready
    state.book_now = claude_resp.book_now

    # ── 8. EMERGENCY HANDLING ────────────────────────────────────────────────
    # Emergency short-circuits all scheduling logic.
    # Turn discipline: return Claude's emergency message and nothing else.
    if claude_resp.is_emergency:
        logger.warning("Emergency flag set — halting scheduling [session=%s]", session_id)
        return ChatResponse(
            assistant_message=claude_resp.assistant_message,
            calendar_event=None,
        )

    # ── 9. TWO-STEP SCHEDULING LOGIC ────────────────────────────────────────
    # Turn discipline: exactly ONE assistant_message is returned per request.
    # final_message is set exactly once below; it is never overwritten.
    calendar_event: Optional[CalendarEvent] = None
    final_message: str = ""

    if claude_resp.book_now:
        # ── STEP 2: User confirmed — execute the booking ──────────────────────
        # Per spec: when book_now=true, Claude sets assistant_message="".
        # The backend is solely responsible for the confirmation message.

        # Guard: ensure all required fields are present before attempting booking.
        missing = [
            label for label, val in (
                ("full name",         state.full_name),
                ("contact info",      state.contact_info),
                ("reason for visit",  state.reason_for_visit),
                ("visit category",    state.visit_category),
                ("preferred date",    state.preferred_date),
                ("preferred time",    state.preferred_time),
            ) if not val
        ]
        if missing:
            # Unexpected incomplete state — ask the user to supply missing fields.
            final_message = (
                f"Before I can book your appointment I still need: "
                f"{', '.join(missing)}. Could you provide those?"
            )
            state.book_now = False
            return ChatResponse(assistant_message=final_message, calendar_event=None)

        # Parse preferred_date + preferred_time into a UTC-aware datetime.
        try:
            start_dt = parse_appointment_datetime(
                state.preferred_date, state.preferred_time  # type: ignore[arg-type]
            )
        except ValueError as exc:
            logger.error("Datetime parse error [session=%s]: %s", session_id, exc)
            final_message = (
                "I had trouble interpreting the appointment date or time. "
                "Could you please confirm the date (YYYY-MM-DD) and time (HH:MM)?"
            )
            state.preferred_date = None
            state.preferred_time = None
            state.confirm_ready = False
            state.book_now = False
            return ChatResponse(assistant_message=final_message, calendar_event=None)

        end_dt = start_dt + timedelta(hours=1)

        # Past-date guard: never allow bookings in the past.
        if start_dt <= datetime.now(timezone.utc):
            final_message = (
                "The selected appointment time appears to be in the past. "
                "Please choose a future date and time."
            )
            state.preferred_date = None
            state.preferred_time = None
            state.confirm_ready = False
            state.book_now = False
            return ChatResponse(assistant_message=final_message, calendar_event=None)

        # Conflict detection: block overlapping 60-minute windows in this session.
        if has_conflict(session_id, start_dt):
            logger.warning(
                "Scheduling conflict [session=%s] at %s", session_id, start_dt
            )
            final_message = (
                f"You already have an appointment that overlaps with "
                f"{state.preferred_date} at {state.preferred_time}. "
                "Would you like to choose a different date or time?"
            )
            # Clear date/time so the user can re-enter without re-confirming stale data.
            state.preferred_date = None
            state.preferred_time = None
            state.confirm_ready = False
            state.book_now = False
            return ChatResponse(assistant_message=final_message, calendar_event=None)

        # Call scheduling stub — synchronous; replace with async I/O in production.
        appointment_id = schedule_appointment(
            session_id=session_id,
            full_name=state.full_name,          # type: ignore[arg-type]
            contact_info=state.contact_info,    # type: ignore[arg-type]
            reason_for_visit=state.reason_for_visit,  # type: ignore[arg-type]
            visit_category=state.visit_category,      # type: ignore[arg-type]
            start_dt=start_dt,
        )

        # Persist the confirmed appointment to the in-memory store.
        scheduled_appointments[session_id].append(
            ScheduledAppointment(
                appointment_id=appointment_id,
                session_id=session_id,
                full_name=state.full_name,           # type: ignore[arg-type]
                contact_info=state.contact_info,     # type: ignore[arg-type]
                reason_for_visit=state.reason_for_visit,   # type: ignore[arg-type]
                visit_category=state.visit_category,       # type: ignore[arg-type]
                start_dt=start_dt,
                end_dt=end_dt,
            )
        )

        # Build human-readable strings for the confirmation message.
        # Convert back to local time for display so "3:00 PM" doesn't become "11:00 PM UTC".
        start_local = start_dt.astimezone()
        readable_date = start_local.strftime("%B %-d, %Y")          # e.g. "February 27, 2026"
        readable_time = start_local.strftime("%-I:%M %p")           # e.g. "3:00 PM"

        # Backend-generated confirmation message.
        # Turn discipline: this is the ONLY message returned to the client.
        final_message = (
            f"Done! Your {state.visit_category} appointment on {readable_date} at "
            f"{readable_time} is confirmed (ID: {appointment_id}). "
            "Is there anything else I can help you with?"
        )

        # Build calendar event for client-side calendar integration.
        calendar_event = CalendarEvent(
            title=f"Vitable Health — {state.visit_category}",
            start_iso=start_dt.isoformat(),
            end_iso=end_dt.isoformat(),
            description=(
                f"Patient: {state.full_name}\n"
                f"Reason: {state.reason_for_visit}\n"
                f"Contact: {state.contact_info}\n"
                f"Appointment ID: {appointment_id}"
            ),
            location="Vitable Health",
        )

        # Clear scheduling fields per spec so the user can book a second appointment
        # without re-entering their identity (full_name + contact_info are retained).
        state.reason_for_visit = None
        state.visit_category = None
        state.preferred_date = None
        state.preferred_time = None
        state.confirm_ready = False
        state.book_now = False

        logger.info(
            "Appointment confirmed | id=%s session=%s start=%s",
            appointment_id, session_id, start_dt.isoformat(),
        )

    else:
        # ── STEP 1 (or ongoing intake): pass Claude's message through ────────
        # Turn discipline: use Claude's message verbatim — never overwrite it.
        final_message = claude_resp.assistant_message

    return ChatResponse(
        assistant_message=final_message,
        calendar_event=calendar_event,
    )


# ─────────────────────────────────────────────────────────────────────────────
# HEALTH CHECK
# ─────────────────────────────────────────────────────────────────────────────
@app.get("/health")
async def health():
    return {"status": "ok", "model": "claude-sonnet-4-6"}
