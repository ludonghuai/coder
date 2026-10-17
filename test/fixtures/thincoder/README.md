# thincoder fixtures

Frames of `thincoder acp` sessions, recorded once and replayed offline by
`test/kernel/thincoder_fixtures_test.dart`: a protocol-surface check that
needs no thincoder installed. Run them first when thincoder is updated —
red means the wire moved, and the frames and the adapter are then brought
back in step together.

One file is one scenario, one JSON object a line:

- `{"fixture": "...", "cwd": "/project", "resume": "<slot>"}` — the first
  line, naming the scenario; `cwd` and `resume` are optional.
- `{"server": {...}}` — a line thincoder wrote, verbatim.
- `{"client": {...}}` — what the adapter wrote at that point, verbatim;
  the replay waits for it and holds the kernel to it.
- `{"turn": "..."}`, `{"answer": "approve_once"}` (or `approve_always`,
  `reject`), `{"cancel": true}` — the user's moves, where the recording had
  them.
- `{"expect": {...}}` — what the conversation shows at the end: `items`
  (`test/kernel/thincoder_fixtures_test.dart` prints them one an item),
  `tasks` (the ids of what runs beside the conversation), `agents` (each
  subagent card and what it said of its own, one a line), `health`,
  `sessionId`, `usage`, `interrupted`, `loading`, `unprompted`.

`unprompted` is whether the last turn ended was one the agent took up on
its own (`thincoder.dev/turn`, an automatic turn with no user message).

`subagent-content` marks its content and tool frames with the subagent they
are by; `subagent-content-legacy` (0.12.74's shape) does not.

To record one: run a session against a real `thincoder acp`, and copy its
stdout lines into a new file as `server` lines, keeping the ids as they
came (`c1`, `c2`, … in the order the client asked). Add the client's own
lines in between, and the user's moves. Recording by hand, as this file
was, is enough: what is under test is the shapes, not the run.
