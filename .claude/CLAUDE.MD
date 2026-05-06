# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them. Don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

For trivial or clearly specified tasks, keep this brief and proceed.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

For UI/UX tasks, "solves the problem" means the visual result must noticeably reflect the user's requested design direction, not merely preserve the existing layout.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it. Don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

Exception: For explicit UI/UX/design requests, visual changes are not considered unnecessary changes. Modify the relevant UI files enough for the requested design improvement to be visible.

## 4. UI/UX and Design Tasks

When the user asks for UI, UX, layout, visual design, styling, mockup, screen polish, or app screen improvement, treat visual refinement as the primary goal.

In UI/UX tasks, do not be overly conservative. It is acceptable and expected to modify:
- layout structure
- spacing and padding
- font sizes and text hierarchy
- colors, opacity, shadows, borders, and radius
- buttons, cards, panels, HUD elements, and visual grouping
- component composition if needed for a better screen
- responsive behavior and mobile usability
- state display and visual feedback

However:
- Keep existing business logic and data flow unchanged unless the user explicitly asks.
- Do not remove existing features unless the user asks or they are clearly replaced by a better visual equivalent.
- Preserve existing function names, public APIs, routes, providers, models, socket events, and server contracts.
- Prefer visual/component-level changes over backend, state management, or architecture changes.
- If a design request conflicts with "Surgical Changes", the design request takes priority for UI-related files only.

For design tasks, success criteria should be visual and user-facing, for example:
- The requested screen visually changes in a noticeable way.
- The layout is cleaner and easier to understand.
- Important actions are easier to find.
- HUD, buttons, cards, and panels match the requested style.
- The app still builds and existing behavior remains intact.

When the user says things like:
- "make it prettier"
- "improve the design"
- "make it look like a real app"
- "make a mockup"
- "polish the UI"
- "make it more game-like"
- "make it look like Naver Map SDK style"
- "adjust the HUD"
- "resize the buttons"
- "change the layout"
- "make the screen match this reference"

Do not respond with only analysis or suggestions. Implement concrete visual changes in the relevant UI files.

## 5. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" -> "Write tests for invalid inputs, then make them pass"
- "Fix the bug" -> "Write a test that reproduces it, then make it pass"
- "Refactor X" -> "Ensure tests pass before and after"
- "Improve UI" -> "Apply visible UI changes, then verify the app builds and the target screen still works"

For multi-step tasks, state a brief plan:

```text
1. [Step] -> verify: [check]
2. [Step] -> verify: [check]
3. [Step] -> verify: [check]
```

Strong success criteria let you loop independently. Weak criteria such as "make it work" require constant clarification.

For UI/UX tasks, verification should include at least:
- Check that the target screen compiles.
- Check that existing interactions remain connected.
- Check that the requested visual change is clearly visible.
- If possible, run `flutter analyze` or the project's existing validation command.

## 6. Implementation Behavior

When implementing:
- Prefer editing existing files over creating new files.
- Prefer small, readable functions over large rewrites.
- Avoid changing architecture unless the request requires it.
- Do not introduce new dependencies unless clearly necessary.
- Do not change package versions unless the task is about dependencies.
- Do not silently ignore failing tests, build errors, or analyzer errors.
- If verification cannot be completed, clearly state what was not verified and why.

For Flutter:
- Preserve existing state management patterns such as Riverpod, Provider, Bloc, setState, or inherited structure.
- Do not move business logic into widgets just to make UI editing easier.
- Keep socket, API, GPS, BLE, map, and background-service logic unchanged unless explicitly requested.
- For design work, focus on widget layout, visual hierarchy, spacing, sizing, colors, overlays, and interaction affordances.
- After changing Dart files, prefer running `flutter analyze`.

For Node.js:
- Preserve existing route names, socket event names, API response shapes, database schemas, and Redis/Kafka contracts unless explicitly requested.
- Do not rewrite service boundaries without a clear reason.
- After changing backend files, prefer running the project's existing test, lint, or start command.

## 7. Communication Style

Be concise but not vague.

Before coding:
- State assumptions only when they affect the implementation.
- Ask clarification only when the task cannot be safely completed without it.
- If the request is clear, implement instead of over-discussing.

After coding:
- Summarize what changed.
- Mention files changed.
- Mention verification performed.
- Mention any remaining risks or follow-up items.

For UI/UX tasks:
- Do not say "I can improve the design" without making changes.
- Do not stop at recommendations when the user asked for implementation.
- Clearly describe the visible before/after result.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, clarifying questions come before implementation rather than after mistakes, and UI/UX requests produce visible design changes without breaking existing logic.