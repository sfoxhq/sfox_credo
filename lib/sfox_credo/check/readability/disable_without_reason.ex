# coveralls-ignore-next-line
defmodule SfoxCredo.Check.Readability.DisableWithoutReason do
  @moduledoc """
  Checks that each `# credo:disable-*` comment has a reason in the comment block
  directly above it.

  Credo reads all text after the instruction as the check name, so a reason on the
  same line stops the disable from working. Put the reason on its own comment line
  above the disable comment:

  ```elixir
  # The DSL macros must come before the module docs.
  # credo:disable-for-this-file Credo.Check.Readability.StrictModuleLayout
  ```

  The check finds all four Credo instructions: `disable-for-this-file`,
  `disable-for-next-line`, `disable-for-previous-line` and `disable-for-lines:<n>`.

  The reason is any full-line comment in the block of consecutive comment lines
  directly above the disable comment. A tool directive such as
  `# quokka:skip-module-directives`, `# coveralls-ignore-next-line` or another
  `# credo:disable-*` comment is not a reason, so this fails:

  ```elixir
  # quokka:skip-module-directives
  # credo:disable-for-this-file Credo.Check.Readability.StrictModuleLayout
  ```
  """

  # coveralls-ignore-next-line
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      A `# credo:disable-*` comment must have a reason on the comment line directly
      above it. Credo ignores a disable comment with text after the check name, so
      the reason cannot go on the same line.
      """
    ]

  def run(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    source = SourceFile.source(source_file)

    case Code.string_to_quoted_with_comments(source) do
      {:ok, _ast, comments} -> find_issues(comments, source, issue_meta)
      {:error, _} -> []
    end
  end

  defp find_issues(comments, source, issue_meta) do
    lines = String.split(source, ["\r\n", "\n"])

    own_line_comments =
      for %{line: line, text: text} <- comments, own_line?(lines, line), into: %{}, do: {line, text}

    for %{line: line, text: text} <- comments,
        [_, instruction] <- [Regex.run(disable_format(), text)],
        not reason_above?(own_line_comments, line - 1) do
      format_issue(
        issue_meta,
        message: "Add the reason for `credo:#{instruction}` on a comment line directly above it.",
        trigger: "credo:#{instruction}",
        line_no: line
      )
    end
  end

  defp own_line?(lines, line) do
    lines
    |> Enum.at(line - 1, "")
    |> String.trim_leading()
    |> String.starts_with?("#")
  end

  defp reason_above?(own_line_comments, line) do
    case Map.fetch(own_line_comments, line) do
      {:ok, text} -> reason?(text) or reason_above?(own_line_comments, line - 1)
      :error -> false
    end
  end

  defp reason?(text) do
    body =
      text
      |> String.trim_leading("#")
      |> String.trim()

    body != "" and not Regex.match?(directive_format(), text)
  end

  # Elixir 1.19 deprecates regexes in module attributes.
  defp disable_format, do: ~r/^#\s*credo:(disable-[\w\-:]+)/
  defp directive_format, do: ~r/^#\s*([\w\-]+:[\w\-]|coveralls-ignore)/
end
