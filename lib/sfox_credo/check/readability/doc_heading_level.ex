# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/sfox_credo/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

# coveralls-ignore-next-line
defmodule SfoxCredo.Check.Readability.DocHeadingLevel do
  @moduledoc ~S'''
  Checks that headings in `@moduledoc`, `@doc` and `@typedoc` start at `##` and don't skip
  levels. ExDoc renders the module name as the page's `h1`, so a `#` heading inside a doc
  competes with it.

  ## What is flagged

  - A level-1 heading: `# Title`, or `Title` underlined with `===`. The underlined form is
    reported on the `Title` line
  - A heading more than one level deeper than the previous heading in the same doc, such
  as `##` followed by `####`

  ```elixir
  @moduledoc """
  # Usage

  Flagged: `#` is reserved for the module name.

  ## Options

  #### Timeouts

  Flagged: skips `###`.
  """
  ```

  [Admonitions][admonitions] are handled explicitly. A block quote whose first content
  (after any blank `>` lines) is a heading with an `{: .class}` attribute is an
  admonition, and its title isn't held to the level rules (nor does it count as the
  previous heading). It is checked against what ExDoc renders as an admonition instead:

  - The title must be `###` or `####`
  - At least one class must be `.warning`, `.error`, `.info`, `.tip` or `.neutral`

  ```elixir
  @moduledoc """
  ## Usage

  > #### Retries {: .tip}
  >
  > Not flagged: an admonition title may follow `##` directly.

  > ## Retries {: .warn}
  >
  > Flagged twice: `##` and `.warn` don't render as an admonition.
  """
  ```

  ## What is not flagged

  - Going back up a level (`###` followed by `##`)
  - A doc whose first heading is deeper than `##`; each doc is checked on its own, so
  a `@doc` may open with `###`
  - `# comment` lines in fenced or indented code blocks
  - `#hashtag` at the start of a line (no space, so not a heading)
  - `Title` underlined with `---` (level 2, which isn't detected)

  ## Parameters

  None.

  ## Known gaps

  - Interpolated docs: each interpolation is scanned as a placeholder, so a heading
    produced by interpolation isn't seen
  - Docs built at compile time (`@moduledoc File.read!("README.md")`) aren't literals, so
    they are skipped
  - Escaped newlines in single-line strings (`@doc "a\n# B"`) are scanned, but every issue
    is reported on the attribute's line
  - HTML blocks are treated as text
  - A block quote ends at the first line without a `>` marker (lazy continuation lines
    aren't part of it)

  [admonitions]: https://ex-doc.hexdocs.pm/readme.html#admonition-blocks
  '''

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    tags: [:docs],
    explanations: [
      check: """
      Documentation headings should start at `##` and should not skip levels. Admonition
      titles must be `###` or `####` with a class ExDoc supports.
      """
    ]

  alias SfoxCredo.Check.Docs
  alias SfoxCredo.Check.Docs.Markdown

  @admonition_classes ~w(warning error info tip neutral)

  def run(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Docs.extract()
    |> Enum.flat_map(&issues_for_doc(&1, issue_meta))
  end

  defp issues_for_doc(doc, issue_meta) do
    lines = Markdown.lines(doc.text)

    {_previous, _quotes, issues} =
      doc.text
      |> Markdown.scan()
      |> Enum.reduce({nil, [], []}, fn
        {:quote_open, offset}, {previous, quotes, issues} ->
          {previous, [offset | quotes], issues}

        {:quote_close, _offset}, {previous, [_ | quotes], issues} ->
          {previous, quotes, issues}

        {:heading, offset, level, _style, text}, {previous, quotes, issues} ->
          line_no = Docs.line_no(doc, offset)

          case admonition_classes(offset, text, quotes, lines) do
            [] -> {level, quotes, heading_issues(level, previous, line_no, issue_meta) ++ issues}
            classes -> {previous, quotes, admonition_issues(level, classes, line_no, issue_meta) ++ issues}
          end

        _event, acc ->
          acc
      end)

    Enum.reverse(issues)
  end

  # ExDoc makes a block quote an admonition when its first child is the heading. Blank `>`
  # lines produce no child, so the heading may follow them.
  defp admonition_classes(offset, text, [start | _quotes], lines) do
    first_child? =
      lines
      |> Enum.slice(start, offset - start)
      |> Enum.all?(&Regex.match?(~r/^[ \t]*(>[ \t]*)+$/, &1))

    with true <- first_child?,
         [attributes] <- Regex.run(~r/\{:([^}]*)\}\s*$/, text, capture: :all_but_first) do
      for [class] <- Regex.scan(~r/\.([\w-]+)/, attributes, capture: :all_but_first), do: class
    else
      _ -> []
    end
  end

  defp admonition_classes(_offset, _text, _quotes, _lines), do: []

  defp admonition_issues(level, classes, line_no, issue_meta) do
    level_issues =
      if level in 3..4 do
        []
      else
        [
          format_issue(issue_meta,
            message: "Use `###` or `####` for admonition titles; ExDoc renders no others.",
            line_no: line_no
          )
        ]
      end

    class_issues =
      if Enum.any?(classes, &(&1 in @admonition_classes)) do
        []
      else
        [
          format_issue(issue_meta,
            message:
              "Unknown admonition class `.#{Enum.join(classes, " .")}`; ExDoc supports " <>
                "`.warning`, `.error`, `.info`, `.tip` and `.neutral`.",
            line_no: line_no
          )
        ]
      end

    level_issues ++ class_issues
  end

  defp heading_issues(1, _previous, line_no, issue_meta) do
    [
      format_issue(issue_meta,
        message: "Start documentation headings at `##`; `#` is reserved for the module name.",
        line_no: line_no
      )
    ]
  end

  defp heading_issues(level, previous, line_no, issue_meta) when is_integer(previous) and level > previous + 1 do
    [format_issue(issue_meta, message: "Heading levels should increase by one.", line_no: line_no)]
  end

  defp heading_issues(_level, _previous, _line_no, _issue_meta), do: []
end
