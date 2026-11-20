# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/sfox_credo/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

# coveralls-ignore-next-line
defmodule SfoxCredo.Check.Readability.DocFencedCode do
  @moduledoc ~S'''
  Checks that code examples in `@moduledoc`, `@doc` and `@typedoc`, doctests included, are
  in fenced code blocks tagged with a language.

  ## What is flagged

  - An indented code block. Doctests (blocks starting with `iex>` or `iex(`) get their own
    message
  - A fence with no language, when `require_language` is `true`
  - A fence with a doctest in it that isn't tagged `elixir` or `iex`; makeup_elixir
    highlights IEx sessions only under those names
  - A `~~~` fence

  ````elixir
  @doc """
  Flagged:

      iex> double(2)
      4

  Fine:

  ```elixir
  iex> double(2)
  4
  ```
  """
  ````

  Fencing a doctest doesn't change what `ExUnit.DocTest` runs: it finds `iex>` prompts on
  every line, and a line starting with a fence ends the expected result. The `iex>` line
  and its result must still share an indentation level inside the fence.

  ## What is not flagged

  - Indented lines inside a fence
  - An indented line straight after paragraph text, with no blank line between them: that
  is a paragraph continuation, not code
  - Continuation lines of a list item, indented under its text
  - Code indented under a nested list item (see the known gaps)

  ## Parameters

  - `require_language`: report fences with no language. Defaults to `true`

  ## Known gaps

  - Indented code is detected at the top level and inside top-level list items only. Code
    under a nested list item isn't flagged
  - Interpolated docs: each interpolation is scanned as a placeholder, so a fence produced
    by interpolation isn't seen
  - Docs built at compile time (`@moduledoc File.read!("README.md")`) aren't literals, so
    they are skipped
  - Escaped newlines in single-line strings (`@doc "a\n\n    code"`) are scanned, but
    every issue is reported on the attribute's line
  - HTML blocks are treated as text
  - A block quote ends at the first line without a `>` marker
  '''

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    tags: [:docs],
    param_defaults: [require_language: true],
    explanations: [
      check: """
      Code examples and doctests in documentation should be in fenced code blocks tagged
      `elixir`, not indented code blocks.
      """,
      params: [
        require_language: "Report fenced code blocks that have no language."
      ]
    ]

  alias SfoxCredo.Check.Docs
  alias SfoxCredo.Check.Docs.Markdown

  @iex_prompts ["iex>", "iex("]
  @elixir_languages ["elixir", "iex"]

  def run(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    require_language? = Params.get(params, :require_language, __MODULE__)

    source_file
    |> Docs.extract()
    |> Enum.flat_map(&issues_for_doc(&1, require_language?, issue_meta))
  end

  defp issues_for_doc(doc, require_language?, issue_meta) do
    events = Markdown.scan(doc.text)
    lines = Markdown.lines(doc.text)

    Enum.flat_map(events, &issues_for_event(&1, events, lines, doc, require_language?, issue_meta))
  end

  defp issues_for_event({:indented_code, offset, text}, _events, _lines, doc, _require_language?, issue_meta) do
    message =
      if String.starts_with?(text, @iex_prompts) do
        "Wrap doctests in a ```elixir fence instead of indenting them."
      else
        "Use a fenced ```elixir block for code examples instead of indenting."
      end

    [format_issue(issue_meta, message: message, line_no: Docs.line_no(doc, offset))]
  end

  defp issues_for_event({:fence_open, offset, char, info}, events, lines, doc, require_language?, issue_meta) do
    line_no = Docs.line_no(doc, offset)

    language =
      info
      |> String.split(~r/\s/, parts: 2)
      |> hd()

    doctest? = fence_has_doctest?(offset, events, lines)

    tilde_issues(char, line_no, issue_meta) ++
      language_issues(language, doctest?, require_language?, line_no, issue_meta)
  end

  defp issues_for_event(_event, _events, _lines, _doc, _require_language?, _issue_meta), do: []

  defp tilde_issues("~", line_no, issue_meta) do
    [format_issue(issue_meta, message: "Use `` ``` `` for code fences, not `~~~`.", line_no: line_no)]
  end

  defp tilde_issues(_char, _line_no, _issue_meta), do: []

  # One issue per fence: a doctest outside an `elixir` fence gets the doctest message even
  # when the fence also has no language. makeup_elixir registers its lexer as both `elixir`
  # and `iex`, so either gets IEx highlighting.
  defp language_issues(language, _doctest?, _require_language?, _line_no, _issue_meta)
       when language in @elixir_languages, do: []

  defp language_issues(_language, true, _require_language?, line_no, issue_meta) do
    [
      format_issue(issue_meta,
        message: "Tag fenced doctests `elixir` or `iex` so they get IEx highlighting.",
        line_no: line_no
      )
    ]
  end

  defp language_issues("", false, true, line_no, issue_meta) do
    [format_issue(issue_meta, message: "Tag fenced code blocks with a language.", line_no: line_no)]
  end

  defp language_issues(_language, _doctest?, _require_language?, _line_no, _issue_meta), do: []

  # Every fence has a close event, even one left open at the end of its block quote or doc.
  defp fence_has_doctest?(open_offset, events, lines) do
    close_offset =
      Enum.find_value(events, fn
        {:fence_close, offset} when offset > open_offset -> offset
        _event -> nil
      end)

    # A fence inside a block quote (an admonition, say) has `>` markers before its lines.
    lines
    |> Enum.slice((open_offset + 1)..(close_offset - 1)//1)
    |> Enum.any?(
      &(&1
        |> String.replace(~r/^[ \t]*(?:>[ \t]?)*/, "")
        |> String.trim_leading()
        |> String.starts_with?(@iex_prompts))
    )
  end
end
