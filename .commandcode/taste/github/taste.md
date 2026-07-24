# github
- When replying to GitHub PR review comments, post replies as inline comments on individual review threads rather than as a single summary comment on the PR. Confidence: 0.65
- For taste-only PRs (small changes to `.commandcode/taste/`), use a shorter CI pipeline or skip the full CI pipeline that runs on code changes — such trivial PRs don't need the full build/check suite. Confidence: 0.65
- When waiting for PR checks to pass, use `gh run watch` instead of `sleep` to poll for completion. Confidence: 0.70
- Before blindly applying bot-generated PR review comments (from gemini-code-assist, coderabbitai, etc.), critically evaluate each comment for validity — not all automated suggestions are correct or worth applying. Confidence: 0.65
- When CI is stuck on a non-substantive post-run cleanup step but all substantive job steps passed, prefer merging the PR directly rather than continuing to debug/cancel/rerun the CI infrastructure issue. Confidence: 0.65
- When merging PRs, use `gh pr merge --squash` with a conventional-commit-formatted subject line and a detailed body explaining the changes, then clean up both local and remote branches. Confidence: 0.60
