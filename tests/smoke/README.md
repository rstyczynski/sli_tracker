# Smoke Tests

Smoke tests are a curated subset of the most critical test cases -- covering
both unit and integration scope -- that run quickly and determine if the build
is testable at all. If smoke tests fail, the build is too broken for full testing.

As defined by industry standard (see [Wikipedia: Smoke testing](https://en.wikipedia.org/wiki/Smoke_testing_(software))):
"Smoke tests are a subset of test cases that cover the most important
functionality of a component or system, used to aid assessment of whether
main functions of the software appear to work correctly."

Smoke tests can be functional tests or unit tests. They answer questions like:
- Does the core function produce valid output?
- Does the basic end-to-end path work at all?
- Is the most critical behavior intact?

## Convention

- File naming: `test_<what>.sh`
- Each script exits 0 on success, nonzero on failure
- Keep tests fast -- smoke is a quick gate, not a thorough suite
- Select the most critical paths; defer edge cases to unit/integration
