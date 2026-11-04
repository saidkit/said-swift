# Surface-contract rules - `native` surface

The reviewer this lane names in `SAID.reviewers:`. It is a **recipe-form** Checker (no agent file, no
`SAID.checkers-dir:`): the reviewer gate indexes the `said-*` block below. Its capture is a process spawn of the
lane's full gate and its judge is an `oracle`: the deterministic `said-recompute` re-runs `make ci` (format, lint,
build, test; `docs/qa/feature-qa-checklist.md`), so a fabricated PASS is caught. It judges the build, not the UI;
a project that needs a UI check adds its own Checker beside this one.

```
said-checker:   native-build
said-governs:   surface=native              # fires on a feature that bears the native surface
said-capture:   process-spawn               # the full gate run as a process
said-judge:     oracle
said-recompute: make ci                     # format-check + lint + build + test; exit 0 = conformant
```
