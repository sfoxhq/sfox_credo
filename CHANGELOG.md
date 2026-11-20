# `sfox_credo` Changelog

## v0.2.0 / 2026-11-20

### New Checks

- Added two checks that flag the use of `inspect/1,2` in log messages and
  metadata: `Check.Warning.LoggerMessageInspect` and
  `Check.Warning.LoggerMetadataInspect`.

  Both check `Logger` and Erlang `:logger` calls and trace `inspect/1,2` calls
  through variable assignments and local wrapper functions. Modules that wrap
  the Elixir `Logger` and provide additional functions are supported through
  the `extra_loggers` and `extra_logger_functions` parameters.

  `Check.Warning.LoggerMessageInspect` also flags `~p`, `~P`, `~w` and `~W` in
  Erlang `:logger` format strings, which flatten terms the same way.

### Bug Fixes

- `Check.Warning.AvoidAtomToString` now flags `Elixir.Atom.to_string/1`.

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
