# `sfox_credo`

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
    {:sfox_credo, "~> 0.1"}
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
  by sFOX. This includes `SfoxCredo.Check.Design.EctoMigrationTimestamp` and
  `SfoxCredo.Check.Warning.AvoidAtomToString`.

When using these plugins, it is _strongly_ recommended that the `enabled`
configuration block be omitted from your `.credo.exs`. Checks to be disabled
should be added to the `disabled` list and additional or reconfigured checks
should be placed in the `extra` list. Otherwise, it will be necessary for you
to manually configure _everything_.

## Semantic Versioning

`sfox_credo` follows [Semantic Versioning 2.0][semver].

[docs]: https://sfox-credo-checks.hexdocs.pm/
[hexpm]: https://hex.pm/packages/sfox_credo
[semver]: https://semver.org/
