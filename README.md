# `sfox_credo`

<!--
SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/sfox_credo/graphs/contributors>

SPDX-License-Identifier: Apache-2.0
-->

[![Hex.pm](https://img.shields.io/hexpm/v/sfox_credo.svg?style=for-the-badge)][hexpm]
[![Hex Docs](https://img.shields.io/badge/hex-docs-purple.svg?style=for-the-badge)][docs]
[![Apache-2.0](https://img.shields.io/hexpm/l/sfox_credo.svg?style=for-the-badge "Apache-2.0")](https://github.com/sfoxhq/sfox_credo/blob/main/LICENCE.md)

<!--
![Coveralls](https://img.shields.io/coverallsCoverage/github/sfoxhq/sfox_credo?style=for-the-badge)
-->

- code :: <https://github.com/sfoxhq/sfox_credo>
- issues :: <https://github.com/sfoxhq/sfox_credo/issues>

Credo checks used for Elixir projects at sFOX.

## Installation

Add `sfox_credo` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sfox_credo, "~> 0.2"}
  ]
end
```

Documentation is found on [HexDocs][docs].

## Usage

`sfox_credo` provides two plugins to add to the profile plugins list in
`.credo.exs`:

- `SfoxCredo.Standard`: Add this to `plugins` to configure standard Credo
  checks (including some that will be in the next minor release) as used by
  sFOX.

- `SfoxCredo.Custom`: Add this to `plugins` to configure Credo checks written
  by sFOX. The checks are grouped by their Credo tag; see
  [Selecting custom checks](#selecting-custom-checks).

When using these plugins, it is _strongly_ recommended that the `enabled`
configuration block be omitted from your `.credo.exs`. Checks to be disabled
should be added to the `disabled` list and additional or reconfigured checks
should be placed in the `extra` list. Otherwise, it will be necessary for you
to manually configure _everything_.

### Selecting custom checks

Each check in `SfoxCredo.Custom` belongs to one group.

- `:correctness` (enabled by default)

  - `SfoxCredo.Check.Warning.AvoidAtomToString`: prefer `to_string/1` over
    `Atom.to_string/1`.

- `:docs` (enabled by default)

  - `SfoxCredo.Check.Readability.DocFencedCode`: code examples and doctests in
    documentation are fenced Elixir blocks.
  - `SfoxCredo.Check.Readability.DocHeadingLevel`: documentation headings
    start at `##` and don't skip levels. Also verifies admonition formatting.
  - `SfoxCredo.Check.Readability.DocListStyle`: documentation lists use `-`
    and aren't indented from the surrounding text.

- `:ecto` (disabled by default)

  - `SfoxCredo.Check.Design.EctoMigrationTimestamps`: Ecto migrations create
    tables with both timestamp columns.

- `:security` (enabled by default)

  - `SfoxCredo.Check.Warning.LoggerMessageInspect`: no `inspect/1` in Logger
    messages.
  - `SfoxCredo.Check.Warning.LoggerMetadataInspect`: no `inspect/1` in Logger
    metadata values.

Change the selection with the `include` and `exclude` plugin params. `exclude`
wins when a group is in both. Any other param, or an unknown group, stops Credo
with an error.

```elixir
plugins: [{SfoxCredo.Custom, include: [:ecto], exclude: [:docs]}]
```

Checks outside the selection aren't registered. Enable or configure a single
check in your own `extra` list:

```elixir
checks: %{
  extra: [
    {SfoxCredo.Check.Readability.DocListStyle, []},
    {SfoxCredo.Check.Warning.LoggerMessageInspect, extra_loggers: [MyApp.Logger]}
  ]
}
```

If `SfoxCredo.Custom` is listed in more than one config file (a project's
`.credo.exs` and its umbrella's, say), the params of the config closest to the
project are used, as with every other Credo setting.

Both plugins register their checks under the config name in effect, so they
also apply with `mix credo --config-name`.

If you use `enabled` in your check configuration, Credo ignores the plugin's
checks; list the checks you want from the groups above in `enabled` yourself.

## Semantic Versioning

`sfox_credo` follows [Semantic Versioning 2.0][semver].

[docs]: https://sfox-credo-checks.hexdocs.pm/
[hexpm]: https://hex.pm/packages/sfox_credo
[semver]: https://semver.org/
