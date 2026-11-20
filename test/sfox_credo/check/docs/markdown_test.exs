defmodule SfoxCredo.Check.Docs.MarkdownTest do
  use ExUnit.Case, async: true

  alias SfoxCredo.Check.Docs.Markdown

  test "reports fences with their character and info string" do
    assert Markdown.scan("```elixir\nfoo()\n```\n\n~~~\nbar\n~~~") == [
             {:fence_open, 0, "`", "elixir"},
             {:fence_close, 2},
             {:fence_open, 4, "~", ""},
             {:fence_close, 6}
           ]
  end

  test "a fence closes only on the same character with at least the same length" do
    text = "````\n```\n~~~~\n````"

    assert Markdown.scan(text) == [{:fence_open, 0, "`", ""}, {:fence_close, 3}]
  end

  test "an unclosed fence runs to the end of the doc, closing one past its last line" do
    assert Markdown.scan("```\n- a\n# b") == [{:fence_open, 0, "`", ""}, {:fence_close, 3}]
  end

  test "an unclosed fence in a block quote closes at the end of the quote" do
    assert Markdown.scan("> ```\n> iex> a\n\n```\nb\n```") == [
             {:quote_open, 0},
             {:fence_open, 0, "`", ""},
             {:fence_close, 2},
             {:quote_close, 1},
             {:fence_open, 3, "`", ""},
             {:fence_close, 5}
           ]
  end

  test "a fence in a list item ends with the item" do
    assert Markdown.scan("- a\n  ```\n  b\nc\n# d") == [
             {:list_item, 0, 0, "-", 2, 0},
             {:fence_open, 1, "`", ""},
             {:fence_close, 3},
             {:heading, 4, 1, :atx, "d"}
           ]
  end

  test "a fence closing outdented from its list item ends the item and opens a new fence" do
    assert Markdown.scan("- a\n  ```\n  b\n```") == [
             {:list_item, 0, 0, "-", 2, 0},
             {:fence_open, 1, "`", ""},
             {:fence_close, 3},
             {:fence_open, 3, "`", ""},
             {:fence_close, 4}
           ]
  end

  test "a blank line doesn't end a fence in a list item" do
    assert Markdown.scan("- a\n  ```\n\n  b\n  ```") == [
             {:list_item, 0, 0, "-", 2, 0},
             {:fence_open, 1, "`", ""},
             {:fence_close, 4}
           ]
  end

  # Were the second line a list item, the indented line would be nested under it.
  test "an ordered item not starting at 1 doesn't interrupt a paragraph" do
    assert Markdown.scan("Released in\n2019. Changes:\n\n      - a") == [{:indented_code, 3, "- a"}]
  end

  test "an empty ordered item doesn't interrupt a paragraph" do
    assert Markdown.scan("a\n1.\n\n   - b") == [{:list_item, 3, 3, "-", 5, 0}]
  end

  test "an empty bullet item doesn't interrupt a paragraph" do
    assert Markdown.scan("a\n-   \n  - b") == [{:list_item, 2, 2, "-", 4, 0}]
  end

  test "an ordered item starting at 1 interrupts a paragraph" do
    assert Markdown.scan("a\n1. b\n   - c") == [{:list_item, 2, 3, "-", 5, 3}]
  end

  test "an ordered item not starting at 1 continues an enclosing list" do
    assert Markdown.scan("1. a\n2. b\n   - c") == [{:list_item, 2, 3, "-", 5, 3}]
  end

  test "a backtick in a backtick fence's info string is an inline code span" do
    assert Markdown.scan("```foo``` is inline\n- item") == [{:list_item, 1, 0, "-", 2, 0}]
  end

  test "reports list items with their indent, marker, content column and parent column" do
    assert Markdown.scan("- a\n  * b\n    + c\n- d") == [
             {:list_item, 0, 0, "-", 2, 0},
             {:list_item, 1, 2, "*", 4, 2},
             {:list_item, 2, 4, "+", 6, 4},
             {:list_item, 3, 0, "-", 2, 0}
           ]
  end

  test "caps the content column per CommonMark" do
    assert Markdown.scan("-    a\n\n-      b\n\n-") == [
             {:list_item, 0, 0, "-", 5, 0},
             {:list_item, 2, 0, "-", 2, 0}
           ]
  end

  test "ordered items produce no event but nest bullets" do
    assert Markdown.scan("10. a\n    - b") == [{:list_item, 1, 4, "-", 6, 4}]
  end

  test "a non-item line indented less than the item's text leaves the list" do
    assert Markdown.scan("- a\n\ntext\n\n  - b") == [
             {:list_item, 0, 0, "-", 2, 0},
             {:list_item, 4, 2, "-", 4, 0}
           ]
  end

  test "a lazy continuation line stays in the item" do
    assert Markdown.scan("- a\nlazy\n  - b") == [
             {:list_item, 0, 0, "-", 2, 0},
             {:list_item, 2, 2, "-", 4, 2}
           ]
  end

  test "thematic breaks are not list items" do
    assert Markdown.scan("* * *\n***\n- - -\n___") == []
  end

  test "reports indented code once per block, including across blank lines" do
    assert Markdown.scan("text\n\n    a\n\n    b\nafter") == [{:indented_code, 2, "a"}]
  end

  test "indented code directly after a heading or a fence, with no blank line" do
    assert Markdown.scan("## A\n    code") == [{:heading, 0, 2, :atx, "A"}, {:indented_code, 1, "code"}]

    assert Markdown.scan("```\n```\n    code") == [
             {:fence_open, 0, "`", ""},
             {:fence_close, 1},
             {:indented_code, 2, "code"}
           ]
  end

  test "indented code on the first line" do
    assert Markdown.scan("    code") == [{:indented_code, 0, "code"}]
  end

  test "tabs in leading whitespace advance to the next multiple of 4" do
    assert Markdown.scan("text\n\n\tcode") == [{:indented_code, 2, "code"}]
    assert Markdown.scan("text\n\n  \tcode") == [{:indented_code, 2, "code"}]
    assert Markdown.scan("- a\n\t- b") == [{:list_item, 0, 0, "-", 2, 0}, {:list_item, 1, 4, "-", 6, 2}]
  end

  test "reports ATX headings" do
    assert Markdown.scan("# a\n## b\n###### c\n####### d\n#e\n#") == [
             {:heading, 0, 1, :atx, "a"},
             {:heading, 1, 2, :atx, "b"},
             {:heading, 2, 6, :atx, "c"},
             {:heading, 5, 1, :atx, ""}
           ]
  end

  test "heading text drops a closing # sequence but keeps a trailing attribute" do
    assert Markdown.scan("## Title ##\n#### Tip {: .tip}") == [
             {:heading, 0, 2, :atx, "Title"},
             {:heading, 1, 4, :atx, "Tip {: .tip}"}
           ]
  end

  test "reports a setext level-1 heading at the start of its paragraph" do
    assert Markdown.scan("Long\ntitle\n===") == [{:heading, 0, 1, :setext, "Long"}]
  end

  test "scans block quote content as its own document, with offsets into the whole text" do
    text = "text\n\n> #### Tip {: .tip}\n>\n> * item\n>\n>       code\n\nafter"

    assert Markdown.scan(text) == [
             {:quote_open, 2},
             {:heading, 2, 4, :atx, "Tip {: .tip}"},
             {:list_item, 4, 0, "*", 2, 0},
             {:indented_code, 6, "code"},
             {:quote_close, 6}
           ]
  end

  test "a fence inside a block quote" do
    assert Markdown.scan("> ```\n> iex> a\n> ```") == [
             {:quote_open, 0},
             {:fence_open, 0, "`", ""},
             {:fence_close, 2},
             {:quote_close, 2}
           ]
  end

  test "a block quote ends at a blank line or a line without a marker" do
    assert Markdown.scan("> a\n\n> b\nc") == [
             {:quote_open, 0},
             {:quote_close, 0},
             {:quote_open, 2},
             {:quote_close, 2}
           ]
  end

  test "nested block quotes" do
    assert Markdown.scan("> > # deep") == [
             {:quote_open, 0},
             {:quote_open, 0},
             {:heading, 0, 1, :atx, "deep"},
             {:quote_close, 0},
             {:quote_close, 0}
           ]
  end

  test "a block quote inside a list item" do
    assert Markdown.scan("- a\n\n  > #### Note {: .info}") == [
             {:list_item, 0, 0, "-", 2, 0},
             {:quote_open, 2},
             {:heading, 2, 4, :atx, "Note {: .info}"},
             {:quote_close, 2}
           ]
  end

  test "a > inside a fence is not a block quote" do
    assert Markdown.scan("```\n> a\n```") == [{:fence_open, 0, "`", ""}, {:fence_close, 2}]
  end

  test "`===` that would be a lazy continuation is not an underline" do
    assert Markdown.scan("- a\n===") == [{:list_item, 0, 0, "-", 2, 0}]
  end

  test "headings and items are not detected inside indented code" do
    assert Markdown.scan("    # comment\n    - item") == [{:indented_code, 0, "# comment"}]
  end

  test "code under a nested list item is tracked but not reported" do
    assert Markdown.scan("- a\n  - b\n\n        # comment") == [
             {:list_item, 0, 0, "-", 2, 0},
             {:list_item, 1, 2, "-", 4, 2}
           ]
  end
end
