Review the git diff saved at the `diff` path in the <review-run> block below.
Cue context: the `context` in that block.

Adhere strictly to your system prompt:
1. Anchor your review strictly to the diff hunks.
2. Formulate 1-3 falsifiable questions targeting concrete failure modes before exploring.
3. Strict read-only analysis: DO NOT run tests, builds, or package commands (no cargo test, npm test, etc.).
4. Use grep, glob, and ranged read (offset + limit) for context.
5. Sweep the 5-category taxonomy checklist (Correctness, Efficiency, Maintainability, Security, Testing & Observability).
6. Save your findings JSON with proof_of_work using cue-review, with exactly the `filename` and `context` given under `output`. Do not add suffixes or rename on collision: the run directory is unique to this run.
7. Report back the saved review artifact path, summary count of findings, and files examined.
