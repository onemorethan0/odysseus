# Upstream drafts — POSTED 2026-08-10

Both artefacts are now filed. Kept here as the record of what was sent:

1. A **new bug report** for the foreground-poll cancellation (not covered by any existing
   issue) → https://github.com/odysseus-dev/odysseus/issues/5981 (open, labelled
   "ready for review", no maintainer reply yet).
2. A **comment on the existing open issue #4653**, whose symptom matches ours but whose
   attributed cause does not →
   https://github.com/odysseus-dev/odysseus/issues/4653#issuecomment (posted, no reply yet).

Per `CONTRIBUTING.md`, agent-driven work opens an **issue first, never a PR** — the policy
names Claude Code explicitly and says agent PRs are closed unreviewed even when correct. So
the one-line fix is offered *inside* the issue body for a maintainer to take or reject.

Repo note: resolved. `pewdiepie-archdaemon/odysseus` was an **org rename** — GitHub redirects
it to `odysseus-dev/odysseus`, which is what `CONTRIBUTING.md` and the issue template point
at. `origin` has been re-pointed to the canonical name.

---

## 1. NEW ISSUE

**Title:** Scheduled/background agent runs are cancelled by the UI's own idle poll (`/api/email/unread-state`), logged as "Stopped by user"

**Install Method:** Manual Python install (pip / venv)
**Operating System:** Windows
*(Found on Windows. The code path is platform-neutral — plain string matching on the request
path — so it should reproduce anywhere the web UI is open.)*

### Steps to Reproduce

1. Create a scheduled task that uses the agent loop (any prompt that takes more than ~60s).
2. Leave the Odysseus web UI open in a browser tab.
3. Trigger the task (webhook or force-run).
4. Watch `task_runs`, or the log.

### Expected

The task runs to completion. Idle UI polling is not user interaction.

### Actual

The run is cancelled within seconds and recorded as:

```
status  = aborted
error   = "Stopped by user"
```

with this in the log:

```
src.task_scheduler - INFO - Stopped 2 background scheduler task(s):
    foreground request GET /api/email/unread-state
```

No user did anything. Observed repeatedly; one run aborted 69s in.

### Cause

`_InteractiveActivityMiddleware` (app.py) calls
`task_scheduler.stop_background_tasks_for_foreground()` for any request that
`should_track_interactive_request()` returns True for. That yielding behaviour is
intentional and documented ("when the user opens or uses Odysseus, foreground interaction
wins immediately").

The problem is only which paths count. `src/interactive_gate.py` has:

```python
_PASSIVE_EXACT_PATHS = {
    "/api/activity/heartbeat",
    "/api/client-perf",
    "/api/tasks/notifications",
    "/api/research/active",
    "/api/email/urgency-state",
}
```

`/api/email/**urgency**-state` is listed; its sibling `/api/email/**unread**-state` is not,
though the UI polls both on a timer. So an open tab is a permanent stream of "foreground
activity" and background work can never finish.

Confirmed present on `dev` (checked `origin/dev`, 2 commits ahead of my checkout; the file
is byte-identical to mine).

### Suggested fix

```diff
     "/api/research/active",
     "/api/email/urgency-state",
+    "/api/email/unread-state",
 }
```

Verified locally with `should_track_interactive_request()`: after the change
`/api/email/unread-state` and `/api/email/urgency-state` are both untracked, while
`/api/chat_stream` and other real interactions still return True. A scheduled agent run then
completed with the UI open, where it had aborted at ~69s before.

### Secondary point

Whatever the path list ends up as, `"Stopped by user"` is misleading when nothing user-driven
happened — it sent me looking for a stray cancel for some time. Something like
"Pre-empted by foreground activity: <path>" would be self-explanatory. There is already a
distinct message for the quiet-window case ("Paused because Odysseus became active"), so the
machinery for a better label exists.

---

## 2. COMMENT ON EXISTING ISSUE #4653

*("Scheduled task agents role-play tool use in prose instead of calling tools" — open.
It attributes the behaviour to model capability, tested with qwen2.5-14b.)*

> I hit this exact symptom and found a cause that is not model capability, so it may be worth
> ruling out before blaming the model.
>
> On my setup the agent was being handed **three tools**. `get_tool_index()` was failing:
>
> ```
> ChromaDB is not reachable at localhost:8100
> ```
>
> With the index dead, RAG retrieval returns nothing and every turn falls back to
> `ALWAYS_AVAILABLE`, which is `{manage_memory, ask_user, update_plan}` — none of which can
> read a file or run a command. The agent then does the only thing left available to it:
> describes what it would do. It reads exactly like a model too weak to call tools, and it is
> actually a model with nothing to call.
>
> Worth checking because the failure is silent — the app starts fine, chat works, and nothing
> surfaces that tool retrieval is dead. A startup warning or a degraded-mode banner when
> `get_tool_index()` returns None would have saved me a long time. (I run a manual venv
> install; Docker users get Chroma from compose, so this may only bite non-Docker setups —
> which is arguably the point, since nothing tells you.)
>
> A second, smaller contributor once Chroma was up: retrieval still did not reliably surface
> the file tools for coding requests. Measured on my install —
> `"read server.py and fix the failing test"` retrieved `bash` and `python` but **not**
> `read_file` or `edit_file`; `"run the test suite and report failures"` retrieved only
> `todowrite`; and `"edit frontend/src/App.jsx to add a button"` retrieved only `edit_file`,
> since that query contains no `_KEYWORD_HINTS` vocabulary at all — just a path.
>
> If useful I can open a separate issue for that with the measurements; it is a tuning
> question rather than a defect, so I did not want to fold it in here.
