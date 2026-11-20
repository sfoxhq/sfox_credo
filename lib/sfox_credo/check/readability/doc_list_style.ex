# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/sfox_credo/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

# coveralls-ignore-next-line
defmodule SfoxCredo.Check.Readability.DocListStyle do
  @moduledoc ~S'''
  Checks that bullet lists in `@moduledoc`, `@doc` and `@typedoc` use `-` and are not
  indented relative to the block they belong to.

  ## What is flagged

  - A bullet list item that uses `*` or `+` (or, with `marker: "*"`, anything but `*`)
  - A list item whose `-` doesn't line up with the text above it: a top-level item must
    start at the doc's left margin, and a nested item must start under the text of its
    parent item

  An item with the wrong marker that is also indented is reported twice, once for each
  problem.

  ```elixir
  @doc """
  Options:

    * `:name` - flagged twice: marker and indentation
  - `:size` - fine
    - `:unit` - fine, nested under the text of `:size`
      - `:base` - flagged: indented past the text of `:unit`
  """
  ```

  ## What is not flagged

  - Ordered list items (`1.`), although bullet items nested under them are checked against
    their content column
  - Thematic breaks (`* * *`, `***`, `- - -`) and emphasis at the start of a line
    (`*emphasis*`)
  - Anything inside a fenced code block
  - A line indented four or more spaces after a blank line with no list open: that is an
    indented code block, which `DocFencedCode` reports
  - `@doc false` and other non-literal docs

  ## Parameters

  - `marker`: the bullet character to require: `"-"`, `"*"` or `"+"`. Defaults to `"-"`
  - `check_indentation`: set to `false` to report only the marker. Defaults to `true`

  ## Known gaps

  - Interpolated docs: each interpolation is scanned as a placeholder, so a list item
    produced by interpolation isn't seen
  - Docs built at compile time (`@moduledoc File.read!("README.md")`) aren't literals, so
    they are skipped
  - Escaped newlines in single-line strings (`@doc "a\n- b"`) are scanned, but every issue
    is reported on the attribute's line
  - HTML blocks are treated as text
  - A block quote ends at the first line without a `>` marker (lazy continuation lines
    aren't part of it)
  '''

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    tags: [:docs],
    param_defaults: [marker: "-", check_indentation: true],
    explanations: [
      check: """
      Bullet lists in documentation should use `-` and line up with the text around them.
      """,
      params: [
        marker: "The bullet character that list items must use.",
        check_indentation: "Report list items that are indented from the surrounding text."
      ]
    ]

  alias SfoxCredo.Check.Docs
  alias SfoxCredo.Check.Docs.Markdown

  @markers ["-", "*", "+"]

  def run(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    settings = %{
      marker:
        params
        |> Params.get(:marker, __MODULE__)
        |> validate_marker!(),
      check_indentation?: Params.get(params, :check_indentation, __MODULE__)
    }

    source_file
    |> Docs.extract()
    |> Enum.flat_map(&issues_for_doc(&1, settings, issue_meta))
  end

  defp validate_marker!(marker) when marker in @markers, do: marker

  defp validate_marker!(marker) do
    raise ArgumentError, "marker must be one of #{inspect(@markers)}, got: #{inspect(marker)}"
  end

  defp issues_for_doc(doc, settings, issue_meta) do
    doc.text
    |> Markdown.scan()
    |> Enum.flat_map(&issues_for_event(&1, doc, settings, issue_meta))
  end

  defp issues_for_event({:list_item, offset, indent, marker, _content_col, parent_col}, doc, settings, issue_meta) do
    line_no = Docs.line_no(doc, offset)

    marker_issues(marker, settings.marker, line_no, issue_meta) ++
      indentation_issues(settings.check_indentation? and indent != parent_col, line_no, issue_meta)
  end

  defp issues_for_event(_event, _doc, _settings, _issue_meta), do: []

  defp marker_issues(marker, marker, _line_no, _issue_meta), do: []

  defp marker_issues(_marker, expected, line_no, issue_meta) do
    others = Enum.map_join(@markers -- [expected], " or ", &"`#{&1}`")

    [
      format_issue(issue_meta,
        message: "Use `#{expected}` for Markdown list items, not #{others}.",
        line_no: line_no
      )
    ]
  end

  defp indentation_issues(false, _line_no, _issue_meta), do: []

  defp indentation_issues(true, line_no, issue_meta) do
    [
      format_issue(issue_meta,
        message: "Don't indent Markdown list items from the surrounding text.",
        line_no: line_no
      )
    ]
  end
end
