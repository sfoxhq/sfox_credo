# `sfox_credo` Changelog

<!--
SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/sfox_credo/graphs/contributors>

SPDX-License-Identifier: Apache-2.0
-->

## v0.2.0 / 2026-11-20

### Breaking Changes

These are _strictly_ breaking changes, but are unlikely to cause any problems
for anyone excluding `SfoxCredo.Check.Design.EctoMigrationTimestamps`.

- `SfoxCredo.Custom` checks are grouped by Credo tag (`:ash`, `:correctness`,
  `:docs`, `:ecto`, `:security`, `:suppressions`) and selected with the
  `include` and `exclude` plugin params. An unknown parameter or group stops
  Credo with an error. When the plugin is listed in more than one config file,
  the params of the config closest to the project are used.

  `:ash` and `:ecto` checks are only compiled if `Ash` or `Ecto` are
  dependencies, and including either group without its library stops Credo
  with an error. `:ecto` is opt-in, so `Check.Design.EctoMigrationTimestamps`
  is now disabled by default; add `include: [:ecto]` to use it.

- `SfoxCredo.Standard` and `SfoxCredo.Custom` register their checks under the
  config name in effect, so they also apply with `mix credo --config-name`.

### New Checks

- Added two checks that flag the use of `inspect/1,2` in log messages and
  metadata: `Check.Warning.LoggerMessageInspect` and
  `Check.Warning.LoggerMetadataInspect`. Both are enabled by default.

  Both check `Logger` and Erlang `:logger` calls and trace `inspect/1,2` calls
  through variable assignments and local wrapper functions. Modules that wrap
  the Elixir `Logger` and provide additional functions are supported through
  the `extra_loggers` and `extra_logger_functions` parameters.

  `Check.Warning.LoggerMessageInspect` also flags `~p`, `~P`, `~w` and `~W` in
  Erlang `:logger` format strings, which flatten terms the same way.

- Added three checks for enforcing certain documentation conventions in
  `@moduledoc`, `@doc`, and `@typedoc`. All three are enabled by default.

  - `Check.Readability.DocListStyle` enforces consistent unordered list bullet
    styles (`-` as the default) and can enforce text-aligned indentation.

  - `Check.Readability.DocFencedCode` enforces that all code blocks use code
    fences and can enforce that all code fences have a language marker.

  - `Check.Readability.DocHeadingLevel` enforces that `#` is not used in a
    documentation block and that headers only increment by one. This check
    also verifies that [admonition blocks][admonitions] are formatted
    correctly with one of the known admonition types.

- Added `Check.Readability.DisableWithoutReason`. It fails on a
  `# credo:disable-*` comment that has no reason on a comment line directly
  above it. Credo ignores a disable comment with text after the check name, so
  the reason cannot go on the same line. This check is enabled by default.

- Added `Check.Refactor.AshCallInEnum`. It fails on an `Ash` data layer call
  (such as `Ash.get!/3` or `Ash.load!/3`) in a function given to `Enum` or
  `Stream`, or in a `for` body, because the call runs once for each element.

  It also follows local functions one level, so `Enum.map(ids, &fetch/1)`
  fails when `fetch/1` calls `Ash`. Bulk actions and loops over chunks are
  batching, so they pass. It skips files in `test/` directories unless you set
  `include_tests: true`. This check is not enabled by default. Add it with
  `[include: [:ash]]`.

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
