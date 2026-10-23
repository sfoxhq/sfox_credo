# `sfox_credo` Changelog

## v0.2.0 / 2026-10-23

- Added `Check.Readability.DisableWithoutReason`. It fails on a
  `# credo:disable-*` comment that has no reason on a comment line directly
  above it. Credo ignores a disable comment with text after the check name, so
  the reason cannot go on the same line.

- Added `Check.Warning.AshCallInEnum`. It fails on an `Ash` data layer call
  (such as `Ash.get!/3` or `Ash.load!/3`) in an `Enum.map/2` or `Enum.each/2`
  function or a `for` body, because the call runs once for each element. It
  skips files in `test/` directories unless you set `include_tests: true`.

- `SfoxCredo.Custom` enables both new checks. A project that upgrades must add a
  reason above each existing `# credo:disable-*` comment.

## v0.1.2 / 2026-10-14

- Really fixed configuration typo for `Check.Design.EctoMigrationTimestamps`.

- Added a unit test that verifies the custom configuration for typos in the
  future, and that every custom check defined here is in the custom
  configuration. (If this policy changes in the future, this test will need
  changing.)

## v0.1.1 / 2026-10-14

- Fixed a typo in configuration for `Check.Design.EctoMigrationTimestamps`
  (and renamed the source file to match the module name).

## v0.1.0 / 2026-10-02

Initial release of Credo checks used for Elixir projects at sFOX.
