# Built-in Writing Modes

Each Mode is a named system-prompt preset for the local LLM. The canonical,
compiled definitions live in [`Sources/GrammarGem/AI/ModeRegistry.swift`](../../Sources/GrammarGem/AI/ModeRegistry.swift);
these JSON files mirror them for transparency and easy editing.

| Mode | Tier | In public repo? |
|------|------|-----------------|
| `polish` | Free | ✅ Yes — the open free core |
| `email`, `post`, `slack`, `academic`, `code` | Paid | Baseline prompts only |

**Soft deterrent (spec §5):** ship the *fully-tuned* paid-mode prompts only in
the signed release build, not in the public repository. The free `polish` mode
is fully open. Custom user Modes (paid) are stored locally per user.
