# `sfox_credo` Changelog

## v0.2.0 / 2026-11-20

### Breaking Changes

These are _strictly_ breaking changes, but are unlikely to cause any problems
for anyone excluding `SfoxCredo.Check.Design.EctoMigrationTimestamps`.

- `SfoxCredo.Custom` checks are grouped by Credo tag (`:correctness`, `:docs`,
  `:ecto`, `:security`) and selected with the `include` and `exclude` plugin
  params. `:ecto` is opt-in, so `Check.Design.EctoMigrationTimestamps` is now
  disabled by default; add `include: [:ecto]` to use it. An unknown parameter
  or group stops Credo with an error. When the plugin is listed in more than
  one config file, the params of the config closest to the project are used.

- `SfoxCredo.Standard` and `SfoxCredo.Custom` register their checks under the
  config name in effect, so they also apply with `mix credo --config-name`.

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

- Added three checks for enforcing certain documentation conventions in
  `@moduledoc`, `@doc`, and `@typedoc`.

  - `Check.Readability.DocListStyle` enforces consistent unordered list bullet
    styles (`-` as the default) and can enforce text-aligned indentation.

  - `Check.Readability.DocFencedCode` enforces that all code blocks use code
    fences and can enforce that all code fences have a language marker.

  - `Check.Readability.DocHeadingLevel` enforces that `#` is not used in a
    documentation block and that headers only increment by one. This check
    also verifies that [admonition blocks][admonitions] are formatted
    correctly with one of the known admonition types.

### Bug Fixes

- `Check.Warning.AvoidAtomToString` now flags `Elixir.Atom.to_string/1`.

[admonitions]: https://ex-doc.hexdocs.pm/readme.html#admonition-blocks

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
