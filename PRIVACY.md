# Privacy

Codex Island reads task metadata from the local Codex SQLite database and tails associated rollout files. It does not modify these files, submit answers or approvals, or send task content to a service. No analytics, telemetry, Island accounts, or remote task storage are included.

The unread count reads Codex desktop's local read-state section in `.codex-global-state.json`. Island does not mark chats read, store account identities, or send this data anywhere. Only local-host unread IDs are counted; unavailable or ambiguous account state is shown as unavailable, not zero. The file is parsed again only when it changes.

Live quota uses Codex's `app-server` stdio interface. Codex performs the authenticated usage read using its own account session; Island does not read authentication tokens or make direct account HTTP requests. This feature is not offline. Codex may perform its ordinary local runtime bookkeeping.

Quota reads are bounded to once per five minutes, including manual refreshes. Available quota notifications require no extra requests. Expired values become unavailable. Settings and presets are stored locally; synthetic previews do not read task data or issue quota requests.

Monitoring and opening Codex do not require Accessibility permission. Questions are handed to Codex for the user to answer. Do not share databases, rollouts, or unredacted screenshots/logs in public bug reports.
