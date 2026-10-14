# `sfox_credo` Changelog

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
