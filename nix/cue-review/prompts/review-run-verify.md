Consolidate and verify the reviewer findings listed under `inputs` in the
<review-run> block below, for the diff named there.

1. Cluster findings from different reviewers that identify the same defect
   at the same code location; note any severe disparity between reviewers
   (e.g. 0 findings vs more than 3 on a substantial diff) in your reply.
2. For each candidate, inspect the actual source with ranged `read` and
   check the finding's `unverified` claims; decide verified, refuted, or
   unconfirmable.
3. Save the result with the `cue-review` tool using exactly the `filename`
   and `context` given under `output`. Set `metadata.run_id`, `base`,
   `head`, and `reviewed_diff` from the block.
4. Reply with the saved path and the counts of verified, refuted, and
   unconfirmable findings, plus actionable findings by severity with exact
   `file:line_start-line_end` locations.
