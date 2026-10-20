# Contributing

How to change vsh without breaking it. The test suite is described in
[doc/TESTING.md](doc/TESTING.md).

## Before you push

* **Run the unit tier.** `tests/vsh-test unit-sandbox` takes seconds and
  runs the same unit tests as CI. The VM tests (`tests/vsh-test core`,
  `tests/vsh-test onboarding`) take minutes. Run them for changes to how
  vsh connects, or leave them to CI.
* **Enable the pre-push hook**, which runs the unit tier for you. Once per
  clone:
  * **With Nix:** `nix develop` enables it.
  * **Manually:** `git config core.hooksPath .githooks`

  Skip it for a single push with `git push --no-verify`.

## Making changes

* **Lint fixes are not automatically safe.** Some shellcheck suggestions
  change behaviour:
  * Inside backticks `\\` becomes `\`; inside `$(...)` it does not. When
    converting, halve the backslashes.
  * Quoting a variable that was unquoted (`grep -E $x` → `grep -E "$x"`)
    stops word splitting and glob expansion.

  Make one commit per shellcheck rule, run the unit tier after each, and
  compare `tests/vsh-test lint` before and after.
* **Changing a message, log line or exit status?** The tests check them.
  Search for the old text (`grep -rn 'old text' tests/`) and update the
  tests in the same commit.
* **Fixing a known bug (KB-n)?** Its test then fails with "KB-n appears to
  be FIXED". That is expected: replace `expect_known_bug` with a plain
  assertion and remove the entry from [TODO.md](TODO.md) in the same
  commit. `tests/vsh-test known-bugs` shows where each one is tested.
* **Fixing a bug without a test?** Write the test first and check that it
  fails without the fix.
* **A VM test fails and the log is not enough?** `tests/vsh-test
  interactive core` boots the test network, so you can run vsh against
  real LXC hosts. See [doc/TESTING.md](doc/TESTING.md#integration-tier).

## Pull requests

Changes go through pull requests, so CI runs the unit and VM tests before
anything reaches `master`. Keep each commit to one change, with its tests
and docs, so that each one passes the tests by itself.
