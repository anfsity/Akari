# Engineering Guidelines

These rules apply to all changes in this repository.

## Read Before Writing

- Read the relevant code, tests, and documentation before making a change.
- Preserve the repository's existing boundaries and conventions unless the change explicitly improves them.
- After every change, review the surrounding code again for dead conditions, variables that are only read once, unnecessary `else` branches after `return`, and other residue.

## Control Flow and Invariants

- Every branch must be reachable. Do not add defensive branches for states that the contract or type system proves impossible.
- Validate inputs and external boundaries once. Trust established internal invariants instead of repeating defensive checks at every layer.
- Prefer explicit control flow over implicit behavior, and direct calls over unnecessary indirection.
- Keep one implementation for each behavior. Do not leave old and new paths coexisting when the new path replaces the old one.

## Abstraction and Refactoring

- Do not generalize speculatively. Without a second real caller, do not add an abstraction layer.
- If a class has one implementation and is unlikely to be replaceable soon, call the implementation directly instead of introducing an interface.
- If a method has one caller and consists of one operation, inline it.
- When multiple implementations of a method or behavior exist, prefer the newest implementation when it materially improves readability or clarity; keep the older implementation when the newer one provides no practical improvement.
- Refactoring must improve the abstraction or clarify ownership; it must not merely move code.
- Delete obsolete code instead of commenting it out.

## Duplication and Business Knowledge

- Treat redundancy as a high-priority code smell.
- DRY means keeping each piece of business knowledge in one authoritative place, not mechanically deduplicating similar-looking code.
- Do not extract code solely because two methods look alike when their business intent differs.
- Consolidate logic when its business meaning is the same, even if the shared logic is only a few lines long.

## Naming and Command-Query Separation

- Name functions precisely for what they do and only what they do.
- Query functions begin with `get`, `find`, `calculate`, `is`, or `has`. They must be pure, idempotent, and free of side effects.
- Command functions begin with a clear action verb such as `create`, `update`, `cancel`, or `send`, and their names must make state changes explicit.
- Use symmetric pairs consistently: `open`/`close`, `lock`/`unlock`, `start`/`stop`, `source`/`target`, and `encode`/`decode`. Do not mix conventions such as `start`/`end` or `lock`/`release` for the same concept.
- A function named `validateUser` may only validate and return a result or throw. If it also creates a user, split the responsibilities or use an explicit name such as `validateAndCreateUser` as a signal that the design needs review.

## Comments

- Write comments for future readers who need the reasoning behind non-obvious code.
- Do not add comments merely to narrate the diff or restate what the code already says.

## Commits

- Keep commits atomic and split changes at the finest reasonable granularity.
- Commit immediately after each discrete addition or modification rather than batching multiple changes together.
- Each commit must represent a single, focused logical change that is self-contained and straightforward to review, revert, or bisect.