# `sfox_credo` for Agents

`sfox_credo` is an Elixir library of Credo checks and Credo plugin
configurations used for Elixir projects at sFOX. It has no application
runtime: everything here runs inside `mix credo`.

## Project guidelines

- Before finishing, run `mix format`, `mix compile --warnings-as-errors`,
  `mix test`, `mix credo --strict`, and `mix dialyzer`, and fix anything they
  report. CI runs the same tasks on Elixir 1.18, 1.19, and 1.20.
- Do not add dependencies of any kind (runtime, optional, dev, or test)
  without discussing it first. See `CONTRIBUTING.md`.
- Do not change `@version` in `mix.exs`.
- Write each check as its own function that decides when it fails. Do not run
  several checks through one shared table or loop. It is harder to read, and a
  new check that does not fit its shape forces a rewrite. Shared _parsing_
  (alias resolution, doc extraction, Markdown scanning) is fine in a helper
  module; the decision to report an issue belongs to the check.

## Writing checks

- Checks live in `lib/sfox_credo/check/<category>/<name>.ex` as
  `SfoxCredo.Check.<Category>.<Name>`, where `<Category>` is one of Credo's
  categories (`Consistency`, `Design`, `Readability`, `Refactor`, `Warning`).
  Shared helpers live under `lib/sfox_credo/check/` and use
  `@moduledoc false`.
- Every check uses `use Credo.Check` with `base_priority`, `category`,
  `param_defaults` (when it takes params), and `explanations` with `check:`
  and one `params:` entry per param.
- Every check's `@moduledoc` describes what is flagged, what is not, the
  params, and the known gaps (things the check cannot see).
- Every check is tagged with exactly one group (`tags: [:correctness]`, one of
  `:correctness`, `:docs`, `:ecto`, `:security`) and listed in `@checks` in
  `lib/sfox_credo/custom.ex`. `test/sfox_credo/custom_test.exs` fails
  otherwise. A new group needs `@groups` (and, if on by default,
  `@default_groups`) updated in the same module.
- Add the check under its group in the README's "Selecting custom checks"
  section and in the `SfoxCredo.Custom` moduledoc's group list, and to the
  unreleased section of `CHANGELOG.md`. Both group lists use the same format
  (`` - `:group` (enabled by default) `` or `(disabled by default)`, with the
  checks nested under it), and `test/sfox_credo/custom_test.exs` fails when
  either doesn't match the checks' tags and `@default_groups`.
- Resolve module names through `alias` the way `SfoxCredo.Check.Aliases` does,
  instead of matching only the literal module name.

## Tests

- Tests mirror the source path under `test/sfox_credo/check/` and use
  `Credo.Test.Case`:

  ```elixir
  """
  defmodule CredoSampleModule do
    def run, do: Atom.to_string(:foo)
  end
  """
  |> to_source_file()
  |> run_check(AvoidAtomToString)
  |> assert_issue()
  ```

- Test both what a check flags and what it must not flag. For every param,
  test its default and a non-default value.
- Assert line numbers
  (`assert_issue(fn issue -> assert issue.line_no == 3 end)`) whenever a check
  computes a line itself.

## When a linter or check fails

A failing check has one of two causes. The code has a real problem, or the
check is wrong for this code. In the first case, fix the code. In the second
case, fix the configuration of the check. Never change code only to make a
check stop matching it:

- Do not reorder arguments, options or keys, rename things, or move code to
  hide it from a check
- Do not add suppression comments (`# credo:disable-…`) or dialyzer ignores
  unless a person asks for them
- If the check is wrong for this code, change its settings in `.credo.exs` as
  narrowly as you can. Add a comment that tells why, and report the change
- If you cannot tell which cause applies, stop and ask

## Comments and documentation written by AI agents

Every comment an AI agent writes or rewrites must start with `AI:`. This
applies to every file type (except `AGENTS.md`) and every comment form:

- Inline and block comments: `# AI: ...`
- Documentation strings: `@moduledoc`, `@doc` and `@typedoc` start with `AI:`,
  for example `@doc "AI: Builds the file path for a document."`. Put `AI:`
  once, at the start of the first line
- Tagged comments: keep the tag first so tools still find it, for example
  `# TODO: AI: ...` and `# FIXME: AI: ...`
- Markdown files (`README.md`, `CHANGELOG.md`, `AGENTS.md`, and the like):
  start every paragraph and list item the agent writes or edits with `AI:`

Also:

- If you rewrite a comment or paragraph a person wrote, add the prefix,
  because the text is now AI-written. Do not add the prefix to text you only
  move or leave unchanged.
- Never remove an `AI:` prefix, even when editing that text. A person removes
  it after reviewing it.
- This does not apply to commit messages or PR descriptions.

## Markdown in documentation strings

These rules apply to `@moduledoc`, `@doc` and `@typedoc`, and this library
ships checks that enforce them:

- Start each list item with `-`, never `*` or `+`
- Put a blank line between the text and the list
- Do not indent the list: each `-` lines up with the text above it
- Indent a wrapped line two spaces, under the item's text
- Put code examples and doctests in a fenced `` ```elixir `` block, never an
  indented block
- Start headings at `##`; `#` is the module name

````elixir
@moduledoc """
`new/2` starts an email with the configured sender.

- Set the body with `Template`
- Send with `Delivery`

```elixir
iex> new(:welcome, to: "a@example.com")
%Email{}
```
"""
````

## Elixir guidelines

- Always write `if` with a full `do`/`end` block, never the keyword form
  (`if condition, do: ..., else: ...`)
- Write a function with the keyword form (`def name(args), do: body`) only
  when the whole function fits on one line. When `mix format` would move `do:`
  or a `when` guard to its own line, use a full `do`/`end` block
- Predicate function names end in `?` and do not start with `is_`. Names like
  `is_thing` are for guards
- Never begin a function or variable name with `maybe`
- Never nest multiple modules in the same file
- Do not use `String.to_atom/1` on input
