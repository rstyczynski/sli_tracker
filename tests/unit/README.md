# Unit Tests

Isolated function and script-level tests. These test individual components
without external dependencies (no OCI, no GitHub API calls).

## Convention

- File naming: `test_<component>.sh` (one file per component, not per sprint)
- New sprint test cases are appended as functions to existing files
- Each script exits 0 if all tests pass, nonzero if any fail
- Scripts should print pass/fail counts in a parseable format
