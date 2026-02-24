# Guided Study Paywall Audit

## Limit/Premium Gate Inventory (short)

| File | Function/View | What it checks | Trigger timing |
|---|---|---|---|
| `Seek/UsageLimitManager.swift` | `canPerform(_:)` | Central gate for `.guidedStudyMessage`, `.saveNote`, `.saveHighlight`; premium bypass via `EntitlementManager.shared.isPremium` | Called before protected actions |
| `Seek/StudyUsageTracker.swift` | `canSendMessage`, `canSendMessageToday`, `incrementAfterSend` | Free daily guided-study message quota (`freeDailyLimit`) | `can...` before send; `incrementAfterSend` after assistant response |
| `Seek/AppState.swift` | `canUseGuidedStudy()`, `presentPaywall(_:onUnlock:)` | Uses `UsageLimitManager` and presents shared paywall | `canUse...` at guard sites before action |
| `Seek/GuidedStudyScreen.swift` | `guardGuidedStudyAccessOrPresentPaywall(pendingMessage:)` | Blocks send/retry/pending-response when guided-study quota is exhausted; opens shared paywall | Before API request in send/retry/resume-pending paths |
| `Seek/GuidedStudyScreen.swift` | `requestAssistantReply(...)` | Increments guided-study usage for free users after successful assistant reply | After API success |
| `Seek/StudyHomeScreen.swift` | `guardGuidedStudyEntryOrPresentPaywall()` | Blocks entry when guided-study quota exhausted; opens shared paywall | Before launch/initialization of Guided Study sheet |
| `Seek/ReaderScreen.swift` | save highlight/note guards | `UsageLimitManager.canPerform(.saveHighlight/.saveNote)` | Before save actions |
| `Seek/ShareManager.swift` | `canShareNow`, `canShareStreakNow` | Separate share daily quota; premium bypass | Before share sheet |
| `Seek/JourneyScreen.swift` | streak share tap handling | Premium check before showing share-limit paywall | Before share-limit paywall presentation |
| `Seek/StoreManager.swift`, `Seek/PaywallViewModel.swift`, `Seek/EntitlementManager.swift` | StoreKit + entitlement state | Subscription status source of truth / premium state | Entitlement updates and purchase/restore flow |

## Guided Study Entry-Point Trace

### 1) New Guided Study chat from Study Home
- Path: `sendInlineChatEntry(...)` -> `prepareLaunch(...)` -> sheet with `GuidedStudyScreen`
- Now checks usage **before** creating a new conversation and **before** opening conversation screen.
- API requests remain blocked by `GuidedStudyScreen.sendMessage(...)` guard.

### 2) Continue Study path
- Path: `continueConversation(...)` / `continueConversation(..., with:)` -> `prepareLaunch(...)`
- Now checks usage **before** opening conversation screen.
- Any send/retry API call remains blocked by `GuidedStudyScreen` guard.

### 3) Selecting a new passage
- Path A (Study Home): `choosePassage()` -> `prepareLaunch(...)`
- Path B (inside Guided Study): `applyPassageSelection(...)`
- Now checks usage **before** passage switch API load (`RemoteDataService.loadChapter`) and **before** creating new conversation for the selected passage.

## Inconsistencies found and fixed
- Entry guards were missing in Study Home launch paths, allowing conversation initialization/sheet presentation before usage check.
- Passage selection in Guided Study allowed chapter load and conversation creation before usage check.
- Fix: Added early guards that use existing central mechanism (`AppState.canUseGuidedStudy()` -> `UsageLimitManager`) and shared paywall context (`.guidedStudyLimit`).

No limit numbers were changed.
No UI redesign was made.
No architecture refactor was performed.
