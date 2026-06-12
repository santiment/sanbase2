defmodule SanbaseWeb.KnowledgeAnswerHTMLTest do
  use ExUnit.Case, async: true

  alias SanbaseWeb.KnowledgeAnswerHTML

  describe "to_html/1" do
    test "expands a {{date:...}} sentinel into a muted grey span" do
      html =
        KnowledgeAnswerHTML.to_html("- [BTC outlook](https://s/insight/1) {{date:2026-01-02}}")

      refute html =~ "{{date:"
      assert html =~ "(2026-01-02)"
      assert html =~ "color: #9ca3af"
    end

    test "expands the 'unknown date' sentinel too" do
      html = KnowledgeAnswerHTML.to_html("x {{date:unknown date}}")

      refute html =~ "{{date:"
      assert html =~ "(unknown date)"
    end

    test "leaves a sentinel-free answer as ordinary rendered markdown" do
      html = KnowledgeAnswerHTML.to_html("**bold** and a [link](https://x)")

      assert html =~ "<strong>bold</strong>"
      assert html =~ ~s(<a href="https://x">link</a>)
      refute html =~ "color: #9ca3af"
    end

    test "renders nil as an empty string rather than raising" do
      assert KnowledgeAnswerHTML.to_html(nil) == ""
    end

    test "does not expand a malformed date token (only our own emitted shape)" do
      html = KnowledgeAnswerHTML.to_html("{{date:not-a-date}}")

      assert html =~ "{{date:not-a-date}}"
      refute html =~ "color: #9ca3af"
    end
  end
end
