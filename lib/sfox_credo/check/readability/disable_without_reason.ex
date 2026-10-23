# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/sfox_credo/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

# coveralls-ignore-next-line
defmodule SfoxCredo.Check.Readability.DisableWithoutReason do
  @moduledoc """
  Checks that each `# credo:disable-*` and `# quokka:skip-*` comment has a reason in the
  comment block directly above it.

  Credo reads all text after the instruction as the check name, so a reason on the same
  line stops the disable from working. Put the reason on its own comment line above the
  disable comment:

  ```elixir
  # The DSL macros must come before the module docs.
  # credo:disable-for-this-file Credo.Check.Readability.StrictModuleLayout
  ```

  A `# credo:disable-*` comment with text after its check name (a reason, or a second
  check name) is reported even when a reason is also above it, because that disable
  matches nothing. A `/regex/` check name may contain spaces.

  The check finds all four Credo instructions: `disable-for-this-file`,
  `disable-for-next-line`, `disable-for-previous-line` and `disable-for-lines:<n>`. It
  also finds the Quokka instructions that skip a rewrite, such as `skip-module-directives`
  and `skip-sort`. `# quokka:sort` asks Quokka to do something instead of skipping it, so
  it needs no reason.

  The reason is any full-line comment in the block of consecutive comment lines directly
  above. Empty comment lines and tool directives (`# credo:...`, `# quokka:...`,
  `# coveralls-ignore-...`) are not reasons, but the check looks past them, so one reason
  can cover several directives:

  ```elixir
  # The DSL macros must come before the module docs.
  #
  # quokka:skip-module-directives
  # credo:disable-for-this-file Credo.Check.Readability.StrictModuleLayout
  ```

  `# coveralls-ignore-*` comments need no reason.

  ## Parameters

  None.

  ## Known gaps

  - Any other comment counts as a reason; the check can't tell whether it explains
    anything
  - Only Credo and Quokka directives are checked. Other suppressions (`@dialyzer`
    attributes, `# sobelow_skip`) are not
  - A file that doesn't parse is skipped
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    tags: [:suppressions],
    explanations: [
      check: """
      A `# credo:disable-*` or `# quokka:skip-*` comment must have a reason on the comment
      line directly above it. Credo ignores a disable comment with text after the check
      name, so the reason cannot go on the same line.
      """
    ]

  def run(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    source = SourceFile.source(source_file)

    # Parse a file for comments only when it may have a directive, just like Credo.
    if Regex.match?(directive_hint(), source) do
      case Code.string_to_quoted_with_comments(source) do
        {:ok, _ast, comments} -> find_issues(comments, issue_meta)
        {:error, _} -> []
      end
    else
      []
    end
  end

  defp find_issues(comments, issue_meta) do
    own_line_comments =
      for %{line: line, text: text} = comment <- comments, own_line?(comment), into: %{}, do: {line, text}

    missing_reasons =
      for %{line: line, text: text} <- comments,
          [_, directive] <- [Regex.run(disable_format(), text)],
          not reason_above?(own_line_comments, line - 1) do
        format_issue(
          issue_meta,
          message: "Add the reason for `#{directive}` on a comment line directly above it.",
          trigger: directive,
          line_no: line
        )
      end

    missing_reasons ++ text_after_check_issues(comments, issue_meta)
  end

  # Credo reads everything after a `credo:disable-*` instruction as one check name (or one
  # `/regex/`), so a reason or a second check name after it makes the disable match
  # nothing, even when a reason is also above it.
  defp text_after_check_issues(comments, issue_meta) do
    for %{line: line, text: text} <- comments,
        [_, directive, checks] <- [Regex.run(credo_disable_format(), text)],
        text_after_check?(checks) do
      format_issue(
        issue_meta,
        message:
          "Credo reads all text after `#{directive}` as one check name, so this disable matches nothing. " <>
            "Put the reason on a comment line above it.",
        trigger: directive,
        line_no: line
      )
    end
  end

  # A comment after code on the same line has no end of line before it.
  defp own_line?(%{previous_eol_count: count}), do: count > 0

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

  # A `/regex/` may contain spaces; anything else with whitespace is more than one name.
  defp text_after_check?(checks) do
    checks = String.trim_trailing(checks)
    String.match?(checks, ~r/\s/) and not String.match?(checks, ~r{^/.+/$})
  end

  # Credo matches `credo:` case-insensitively.
  defp disable_format, do: ~r/^#\s*(credo:disable-[\w\-:]+|quokka:skip-[\w\-]+)/i
  defp credo_disable_format, do: ~r/^#\s*(credo:disable-[\w\-:]+)\s*(.*)$/i
  # Only the known tool prefixes, so `# Note:upstream bug` is a reason, not a directive.
  defp directive_format, do: ~r/^#\s*(credo:|quokka:|coveralls-ignore)/i
  defp directive_hint, do: ~r/credo:disable|quokka:skip/i
end
