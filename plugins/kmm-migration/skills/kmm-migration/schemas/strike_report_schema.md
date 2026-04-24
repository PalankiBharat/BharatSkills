# strike_report schema

> See `references/three_strike_protocol.md` for when this fires. This
> file codifies the required structure.

## Path

`kmm_migration/reports/<feature>/strikes/<ISO-timestamp>_<subagent>.md`

## Structure

(Identical to the template in `references/three_strike_protocol.md` —
replicated here for validators.)

## Validation rules

- Three Attempt sections, each with Tactic / Output observed / Why it
  failed.
- A Pattern across attempts section, non-empty.
- A Requesting section with one of the three canonical values.
