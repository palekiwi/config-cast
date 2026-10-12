Consolidate and verify the reviewer findings listed under `inputs` in the
<review-run> block below, for the diff named there.

Your working directory is a checkout of the reviewed head commit. Follow
your verification contract, then save the result with the `cue-review` tool
using exactly the `context` and `filename` given under `output`. Set
`metadata.run_id`, `base`, `head`, and the diff path from the block.
