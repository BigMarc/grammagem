# Grammarly Value Teardown -> GrammarGem Plan

*Senior product + Swift engineering review. Every claim below is grounded in the current GrammarGem source. File references use absolute paths; the load-bearing bug is the mis-casing in `SystemGrammarEngine.swift:42-45`.*

---

## 1. Executive summary — what makes Grammarly FEEL valuable (priority order)

Grammarly's perceived value is NOT its grammar engine. It is a stack of interaction and psychology layers on top of a competent engine. Ranked by leverage for a one-time-purchase, on-device Mac utility:

1. **Trustworthy correction quality (the foundation).** Every felt-value mechanic above it collapses if a fix is wrong. Grammarly's "accept-accept-accept" rhythm only works because in-place application is reliable and casing/context is preserved. GrammarGem's engine currently *demonstrably violates this* (`problemm` -> `Problem` mid-sentence). Fix this first; nothing else matters until it's solid.

2. **The fix-as-button atomic loop: read the fix and apply it in one motion.** Grammarly's clickable green replacement chip collapses diagnosis + remedy + action into a single low-friction act, with a cheap, always-present dismiss so saying no is as easy as saying yes. GrammarGem has an `Apply` button but no dismiss/ignore/add-to-dictionary, no keyboard accept, and the apply path is brittle (whole-field AX overwrite).

3. **Categorization + counts + a score: turning a wall of red into a finite, beatable list.** Four named, color-coded buckets, per-category count chips, one running issue badge, and a 0-100 score convert dread into a checklist with a meter that only goes up. GrammarGem has a raw issue count (3 colors) and *zero* score concept.

4. **The rigged first-run "wow": guaranteed visible win in under 60 seconds.** A pre-seeded, error-salted demo doc means the product proves itself before asking for anything. GrammarGem's onboarding only handles Accessibility + model download — it never demonstrates the correction loop at all.

5. **Ongoing perceived value without surveillance: progress you can see.** Grammarly uses cloud percentiles + weekly behavioral emails. GrammarGem can recreate the *feeling* — self-vs-self, fully on-device — with a local score trend, streaks, milestones, and a "subscription you didn't pay" money figure. The plumbing (`UsageStats.perDay`) already exists.

6. **The generative "writing partner" layer: hand me the better sentence, not just the flag.** Sentence rewrites, tone detection/adjustment, conciseness. This is real value but is currently 100% simulated (`MLXEngine.swift` is a string-hack stub) and gated by a daily counter. It is the right *paid* tier, but it must produce real output before it can be sold.

The strategic asymmetry to exploit throughout: every Grammarly value moment carries an implicit "and you'll pay again next year." GrammarGem's identical mechanics should be framed "yours once, forever, on this Mac."

---

## 2. Mechanic-by-mechanic: how Grammarly does it -> how GrammarGem should do it

### Mechanic 1 — Trustworthy correction quality (see §3 for the full engineering plan)
- **Grammarly:** ranks by confidence, suppresses low-confidence edits, never garbles surrounding text, preserves casing, and limits bulk-apply to high-confidence objective mechanics only.
- **GrammarGem today:** `SystemGrammarEngine` blindly trusts `NSSpellChecker.correction(forWordRange:)`, which is sentence-position-aware and capitalizes a word it thinks starts a sentence — producing `problemm` -> `Problem` mid-sentence (`SystemGrammarEngine.swift:42-45`). `Suggestion` has no confidence/severity/alternatives (`Models.swift:48-59`). Default `correct()` applies *every* suggestion including no-op grammar flags where `replacement == original` (`GrammarEngine.swift:22-29`).
- **Do:** real Harper FFI; case/whitespace post-processing; add `confidence`/`severity`/`alternatives` to `Suggestion`; never auto-apply no-ops or low-confidence flags.
- **Files:** `SystemGrammarEngine.swift`, `HarperEngine.swift`, `GrammarEngine.swift`, `Models.swift`, `harper-ffi/`.
- **Impact: high · Effort: L**

### Mechanic 2 — The fix-as-button atomic loop (+ dismiss / ignore / add-to-dictionary)
- **Grammarly:** the suggested word *is* the button (green = go/safe/done); an always-present cheap dismiss (trash/Esc) and add-to-dictionary make accepting feel safe; Tab-to-navigate / Enter-to-accept / Esc-to-dismiss removes the mouse round-trip.
- **GrammarGem today:** `FieldCard` shows a message + one `original -> replacement` + a small `Apply` button (`LiveCheckView.swift:104-119`). There is **no dismiss, no ignore, no add-to-dictionary, no keyboard accept.** Per-issue `apply()` bails silently if the field changed at all since the snapshot (`LiveMonitor.swift:82-89`), and even single-issue apply rewrites the *whole* AX value (`LiveMonitor.swift:101-103`), risking caret/undo/formatting loss.
- **Do (realistic for a cross-app AX tool — we cannot draw a green chip inside arbitrary apps):**
  - Make the replacement text itself the primary tappable control in the card (the chip *is* the fix), styled by category color.
  - Add a per-suggestion overflow: **Dismiss** (model a `dismissedIDs: Set<UUID>` on the monitor so it survives re-scans), **Ignore word** / **Add to dictionary** (route into `PersonalDictionary` -> `ignoreList`), gated by `freeDictionaryCap`.
  - Add **keyboard flow inside the Live Check panel**: ↑/↓ or Tab to move selection, Return to apply, Delete/Esc to dismiss. This is fully feasible because the panel is our own SwiftUI window.
  - Replace whole-field AX write with **targeted span insertion** where the element supports `kAXSelectedTextRangeAttribute` + `kAXSelectedTextAttribute` (set selection to the issue range, then set selected text to the replacement) — preserves caret and undo. Fall back to whole-value only when selection-set is unsupported.
  - Make per-issue apply **rebase** instead of bail: if the live value changed, re-locate the span by matching `original` near the old offset rather than refusing to act.
- **Files:** `LiveCheckView.swift`, `LiveMonitor.swift`, `Models.swift`, `PersonalDictionary.swift`, `AppState.swift`, `TextCapture`.
- **Impact: high · Effort: M**

### Mechanic 3 — Categorization, counts, and an on-device document score
- **Grammarly:** four named buckets (Correctness/Clarity/Engagement/Delivery) each with a color and a count chip that doubles as a filter; one master running badge; a 0-100 percentile score that ticks up on every accept; cards ordered by severity (objective errors first) so the early wins build trust.
- **GrammarGem today:** `GrammarKind` has 6 cases but `.punctuation` is dead; the panel reduces everything to 3 dot colors (`LiveCheckView.swift:136-142`); `issueCount` is a raw sum (`LiveMonitor.swift:32`); there is **no score, no per-category chips, no severity ordering, no filter**.
- **Do (on-device, no cloud, no percentile-vs-others):**
  - Introduce GrammarGem's own named buckets that fit the engine: e.g. **Correctness** (spelling/grammar/punctuation), **Clarity** (phrasing/conciseness — from the real LLM), **Polish** (repetition/capitalization/style). Use original color semantics (do NOT clone Grammarly's exact red/blue/green/purple mapping or wording).
  - Add **count chips per bucket** in the panel header that filter the card list; keep the menu-bar badge as the master tally (`MenuBarLabel`).
  - Compute a **local cleanliness score** at check-time: a deterministic function of issues-per-100-words by severity (e.g. `100 - weighted_issues`). It is honest because it's defined relative to *this document*, not a hidden user corpus. Show it on the card header and trend it on the dashboard.
  - **Order cards by severity then document position** (objective spelling/grammar first) so the first accept is a high-confidence win.
  - Critical: the score must reflect the *honest* free promise — grammar/spelling is unlimited and fully resolvable, so a free user CAN reach a clean score. Do **not** manufacture a permanently-nonzero count to force upgrades (that's Grammarly's locked-bucket trick and it contradicts our positioning — see §5).
- **Files:** `Models.swift` (`GrammarKind` cleanup, add `severity`), `LiveMonitor.swift`, `LiveCheckView.swift`, `MenuBarContent.swift`, `DashboardView.swift`, a new `WritingScore` helper.
- **Impact: high · Effort: M**

### Mechanic 4 — The first-run "wow" (see §4 for the full sequence)
- **Grammarly:** land in an error-salted demo doc -> "we found N issues" -> one-click fixes vanish underlines + decrement counter -> goal setup -> install-everywhere prompt at the dopamine peak.
- **GrammarGem today:** `OnboardingView` only covers Accessibility + model download (`OnboardingView.swift`); it never shows the correction loop.
- **Do:** add an in-app demo step with a pre-seeded sample, a "we found N things to fix" reveal, and a satisfying one-click-to-clean animation — *before* asking for nothing-but-praise (no install-everywhere pressure; we're already system-wide). Detail in §4.
- **Files:** `OnboardingView.swift`, plus a small `DemoDocument` view reusing the highlight + apply UI.
- **Impact: high · Effort: M**

### Mechanic 5 — Ongoing perceived value (privacy-native, self-vs-self)
- **Grammarly:** 0-100 score, weekly Insights email ("more productive than X% of users"), lifetime words-checked counter, streaks — all cloud + behavioral-email, the exact surveillance we market against.
- **GrammarGem today:** `UsageStats` tracks `totalCorrections`, `totalAIActions`, `totalWords`, and `perDay` (`UsageStats.swift`); the dashboard shows four tiles + a 7-bar chart, but **no score, no streak, no week-over-week, no milestone, no money-saved figure**. `estimatedMinutesSaved` is a crude untuned constant (`8s/correction + 45s/AI-action`). Stats are invisible outside the main window.
- **Do (all local, no telemetry, stops nagging the moment they own it):**
  - **Local writing-score trend** on the dashboard (from Mechanic 3), compared only to the user's own past.
  - **Streak + milestones** from existing `perDay` data ("7-day streak", "1,000th correction", "100k words polished") — cheap, high word-of-mouth, and the right re-engagement hook for a no-renewal product.
  - **"Subscription you didn't pay" figure** — translate usage into money: the marketing site already hammers "~\$144/yr vs pay once," but the *app* never does. Show "You've polished N times — that's the price of GrammarGem recovered M times over," computed locally. This is the strongest one-time-purchase value teaser and it lives where the user actually is.
  - **Week-over-week delta** on the bar chart and a lightweight in-app weekly recap card (NOT an email; no pipeline, no surveillance).
  - **Surface one stat in the menu bar dropdown** (the most-seen surface) so value reminders don't require opening the dashboard.
  - Tune `estimatedMinutesSaved` to scale by words changed / action type so the headline "was it worth it?" number is credible.
- **Files:** `UsageStats.swift`, `DashboardView.swift`, `MenuBarContent.swift`, `web/src/lib/content.ts` (replace PLACEHOLDER stats/testimonials before launch).
- **Impact: high · Effort: M**

### Mechanic 6 — The generative "writing partner" layer (real LLM, honest gating)
- **Grammarly:** sentence rewrites ("Replace with This Version" + Highlight-Changes diff), tone detection (emoji + label), tone adjustment, conciseness, GrammarlyGO — all one-click, reversible, before/after.
- **GrammarGem today:** `MLXEngine` is a stub doing `replacingOccurrences` string hacks (`MLXEngine.swift`); `tidy()` even re-introduces casing risk; `detectTone` keys off substrings. `ModelManager` downloads real weights but nothing loads them. Gated by `freeDailyAIActions = 10` shared across rewrite/tone/Ask/translate.
- **Do:**
  - Wire the **real MLX model** from `ModelManager.modelsDirectory` (the download is currently a dead-end); uncomment `mlx-swift` in `Package.swift`.
  - Adopt the **one-click + reversible + before/after diff** delivery contract for every rewrite — this is what neutralizes "the AI is taking over my voice."
  - Keep the **honest quantity gate**: free users get *real, full-quality* output, just rationed (the daily counter), plus Polish mode only. This is the parity-respecting tease — satisfaction-driven ("I keep hitting the limit / I want my own modes / I want it on my other Mac"), not anxiety-driven.
  - Real **tone detection** (label + emoji) is the highest-value non-grammar feature; it delivers value on grammatically perfect text. Build it once the model is live.
- **Files:** `MLXEngine.swift`, `AIEngine.swift`, `ModelManager.swift`, `Package.swift`, `FeatureGate.swift`, `TextReplacementCoordinator.swift`, `WritingModesView.swift`.
- **Impact: high · Effort: L** (model integration is the long pole)

---

## 3. Correction-QUALITY: the path to trustworthy fixes (this underpins ALL perceived value)

The engine is the load-bearing wall. Today it is `NSSpellChecker` + a ~6-rule regex stub, and it ships a trust-destroying casing bug. Here is the ordered path.

### 3.1 Fix the casing/whitespace bug NOW (cheap, immediate)
Root cause: `SystemGrammarEngine.swift:42-45` blindly uses `checker.correction(forWordRange:)`, which is sentence/position-aware and returns a capitalized guess for a token it believes starts a sentence — so a mid-sentence `problemm` comes back `Problem`.

**Post-process every spelling replacement to preserve the original token's casing** unless the token is a true sentence start or proper noun:
- If `original` is all-lowercase, lowercase the replacement's first letter.
- If `original` is Capitalized (single leading cap), match that.
- If `original` is ALL-CAPS, upper-case the replacement.
- Only adopt the corrector's case when the token is at a genuine sentence boundary (preceded by `.?!` + space, or string start). Also trim/normalize whitespace so a replacement never injects a stray leading/trailing space.

This is a ~20-line transcase helper applied at suggestion-build time. It removes the single most visible trust failure before any deeper work.

### 3.2 Stop auto-applying garbage
- `GrammarEngine.correct()` (`GrammarEngine.swift:22-29`) applies **every** suggestion including grammar flags where `replacement == original` (the no-op flags emitted at `SystemGrammarEngine.swift:51-54` and `:67-70`). Filter these out of the bulk path entirely — a no-op flag must never be part of "Fix all," and a low-confidence guess must never auto-apply.
- "Fix all" should be **trust-scoped like Grammarly's bulk accept**: only high-confidence objective mechanics (spelling/grammar/punctuation), never subjective rewrites.

### 3.3 Enrich the data model
`Suggestion` (`Models.swift:48-59`) needs:
- `confidence: Double` (gate auto-apply below a threshold; show low-confidence ones as optional, never bulk-applied).
- `severity` (drives ordering and the score weighting).
- `alternatives: [String]` — `NSSpellChecker.guesses()` already returns multiple candidates but only `.first` is kept (`SystemGrammarEngine.swift:41`); surface the rest so the card can offer "other suggestions."
- `ruleID`/`source` — so feedback (accept/dismiss) can later tune ranking and so we can attribute a fix to Harper vs NSSpellChecker.

### 3.4 Integrate the real Harper core (the big precision unlock)
`harper-ffi/` is an empty README; `Package.swift` comments out all real deps. Stand up the Rust crate behind a C-FFI static lib (`harper_check(text) -> spans`), map spans into `Suggestion`, and keep the protocol boundary so the rest of the app is unchanged. This brings real subject-verb agreement, article/preposition usage, comma/apostrophe rules, commonly-confused pairs, etc. — the category coverage NSSpellChecker structurally cannot provide. De-dup against NSSpellChecker as today (`overlaps`), but prefer Harper where both fire.

### 3.5 Populate the dead `.punctuation` category
`.punctuation` is declared but never emitted, yet punctuation is one of the highest-volume real-world error classes. Harper covers most of it; this fills the gap and makes the new category chips (Mechanic 3) meaningful.

### 3.6 Incremental, async, grapheme-safe checking
- Today: whole-document, synchronous, `DispatchQueue.main.sync` on a 1.6s poll, truncated at 4000 chars (`LiveMonitor.swift:46,174`), frontmost window only. Move to **debounced incremental re-check of changed spans** with caching of unchanged ranges; keep the heavy AX traversal off-main (already done) but get the spell/grammar pass off the main thread too once Harper is FFI-based (no `NSSpellChecker` main-thread requirement).
- Validate that replacement sub-ranges fall on **grapheme boundaries** (emoji/combining marks) before applying — only a coarse bounds check exists today (`SystemGrammarEngine.swift:63`).

### 3.7 Feedback loop
Wire dismiss / add-to-dictionary (Mechanic 2) back into ranking so repeated false positives stop nagging — this is the "it learns" trust signal. Today `ignoreList` only suppresses; long-term, dismiss counts per `ruleID` can down-rank a noisy rule.

**Sequencing:** §3.1 + §3.2 this week (trust-critical, tiny). §3.3 alongside Mechanic 2. §3.4–§3.6 are the real Harper milestone. §3.7 last.

---

## 4. The first-run "wow" sequence for GrammarGem (original copy)

Goal: a guaranteed visible win in under 60 seconds, *inside our own window* (we don't need Grammarly's blank-canvas demo trick or its install-everywhere upsell — we're already system-wide). Onboarding today (`OnboardingView.swift`) skips this entirely.

Proposed flow:

1. **Welcome (1 line):** "A private writing assistant that lives in your menu bar and fixes text in every app — all on this Mac." (existing copy is close; keep it.)

2. **The rigged win — a live mini-demo BEFORE any permission ask.** Show a short pre-written paragraph salted with obvious, safe errors (a misspelling, a repeated word, a lowercase "i", a missing period). Render it with the highlight UI already built in `LiveCheckView.highlighted(...)`. Above it: **"We spotted N things to tidy up."** (count = guaranteed, because the sample is fixed.)

3. **One satisfying click.** A single "Clean it up" button animates the highlights resolving one by one; the count ticks to 0; the paragraph visibly improves. This is the operant loop — trivial action, immediate visible reward — experienced once, on rails, with zero risk. (Reuse the apply path; it's a local string, not a live AX element, so it's completely safe.)

4. **The reveal:** "That's GrammarGem. It does this in Mail, Slack, Notes, your browser — everywhere you type." Then the *first* ask: **Accessibility** (the existing step 2 / `stepCard`), now framed as "Turn it on everywhere."

5. **Optional model step:** keep the existing "Download the on-device model (optional) — grammar works instantly with no download" card. Frame the AI features as a bonus, not a blocker.

6. **No install-everywhere nag, no timed discount, no streak guilt.** End on a calm "You're all set" with one honest line about ownership: "Yours once. No subscription, nothing leaves your Mac."

Guardrails: the demo must use *original* sample text (not Grammarly's), and the count/score must be real (computed by our engine on the sample), never theatrical.

---

## 5. Do NOT copy (dark patterns + claims we can't truthfully make)

These are Grammarly mechanics that either depend on infrastructure we reject or that would corrode the trust/privacy moat that *is* the product.

1. **The premium-issue anxiety counter ("14 advanced issues you can't fix").** It works by detecting problems the engine deliberately won't fix. It clashes head-on with our promise that grammar/spelling/punctuation is unlimited and fully resolvable for free. Do not manufacture a permanently-nonzero count or a "score capped until you upgrade" gate.

2. **Two-tier gold-vs-red underlines (a second class of locked grammar issues).** Our underlines are all free and all resolvable; there is no second class to color differently. Inventing one betrays the core differentiator.

3. **Blur/lock a result we already computed.** On-device + open-source, hiding output we generated is both trivially bypassable and brand-corrosive. Gate by **quantity/frequency** (the daily counter) and **breadth** (modes, multi-device, snippets, larger model) — never by hiding the quality of a single result.

4. **Cloud percentile comparisons ("more productive than X% of users").** Requires an account + aggregate corpus + telemetry — the exact surveillance we market against. Replace with **self-vs-self** local trends.

5. **Behavioral weekly emails / re-nag pipeline.** For a one-time purchase there is no subscription to keep warm; post-purchase nagging is pure annoyance. Any weekly recap must be **in-app, local, opt-in, and stop entirely once they own it.**

6. **Countdown/limited-time discount urgency** (Grammarly's Day-7 40% timer). Manufactured scarcity undercuts the honest "buy once, fair price" positioning.

7. **Lifetime "total words checked" framed as cloud sunk-cost-to-lose.** A local milestone counter is fine and good; framing it as "you'll lose your history if you leave" is a retention dark pattern with no place in a no-renewal product.

8. **Unsubstantiated social proof.** `web/src/lib/content.ts` STATS (200k+ downloads, 4.9 rating) and all TESTIMONIALS are explicitly flagged PLACEHOLDER. Do not ship these as fact — replace with real numbers or remove before launch.

Positive reframe to keep: surface locked paid features (modes, app-aware, snippets, larger model) honestly — "Unlock all of this once. Yours forever, no subscription." Same mechanism (visible locked features), stronger close (no recurring cost objection).

---

## 6. Prioritized roadmap

### NOW (trust + the atomic loop — ship-blockers for credibility)
1. **Fix the casing/whitespace post-processing bug** (§3.1). `SystemGrammarEngine.swift`. *high / S.*
2. **Stop bulk-applying no-ops and low-confidence guesses** (§3.2). `GrammarEngine.swift`, `SystemGrammarEngine.swift`. *high / S.*
3. **Dismiss / Ignore / Add-to-dictionary + keyboard accept in the Live Check panel** (Mechanic 2). `LiveCheckView.swift`, `LiveMonitor.swift`, `Models.swift`, `PersonalDictionary.swift`. *high / M.*
4. **Targeted span apply via AX selection instead of whole-field overwrite; rebase instead of bail** (Mechanic 2). `LiveMonitor.swift`, `TextCapture`. *high / M.*
5. **First-run rigged-win demo** (§4). `OnboardingView.swift`. *high / M.*

### NEXT (organize + the value loop)
6. **Named buckets + per-category count chips + severity ordering + filter** (Mechanic 3). `Models.swift`, `LiveMonitor.swift`, `LiveCheckView.swift`. *high / M.*
7. **On-device writing score (per-doc) + dashboard trend** (Mechanics 3 & 5). `WritingScore` helper, `LiveCheckView.swift`, `DashboardView.swift`. *high / M.*
8. **Streaks + milestones + "subscription you didn't pay" money figure + menu-bar stat** (Mechanic 5). `UsageStats.swift`, `DashboardView.swift`, `MenuBarContent.swift`. *high / M.*
9. **Enrich `Suggestion` with confidence/severity/alternatives + "other suggestions" in card** (§3.3). `Models.swift`, `SystemGrammarEngine.swift`, `LiveCheckView.swift`. *medium / M.*

### LATER (real engine + real partner layer)
10. **Real Harper FFI integration + populate `.punctuation` + grapheme safety + incremental async re-check** (§3.4–§3.6). `harper-ffi/`, `HarperEngine.swift`, `SystemGrammarEngine.swift`, `LiveMonitor.swift`, `Package.swift`. *high / L.*
11. **Wire the real MLX model (load downloaded weights) + one-click/reversible/before-after diff for rewrites + real tone detection** (Mechanic 6). `MLXEngine.swift`, `ModelManager.swift`, `Package.swift`, `TextReplacementCoordinator.swift`. *high / L.*
12. **Replace PLACEHOLDER web social proof/testimonials before launch** (§5). `web/src/lib/content.ts`. *medium / S.*

---

*Throughline: ship trust first (correction quality + a safe, reversible accept loop), then make the work feel finite and rewarding (buckets, counts, a local score), then sell ongoing value honestly (self-vs-self progress, money saved, lifetime ownership) — and build the generative partner tier on a real model with a reversible, before/after contract. Every Grammarly mechanic translates if you swap cloud-surveillance for on-device self-comparison and recurring-nag for one-time honesty.*
