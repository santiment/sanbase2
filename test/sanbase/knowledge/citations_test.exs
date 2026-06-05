defmodule Sanbase.Knowledge.CitationsTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge.Citations

  defp registry() do
    [
      %{id: 1, source: :faq, prefix: "FAQ", label: "What is MVRV?", url: "https://s/faq/1"},
      %{
        id: 2,
        source: :insight,
        prefix: "Insight",
        label: "Understanding Market Expectations",
        url: "https://s/insight/2"
      },
      %{
        id: 3,
        source: :academy,
        prefix: "Academy",
        label: "Getting Started for Traders",
        url: "https://s/academy/3"
      }
    ]
  end

  defp json(map), do: Jason.encode!(map)

  describe "render/2 inline citations" do
    test "expands a bare [id] token into a full clickable markdown link" do
      content =
        json(%{
          "answer" => "Social volume can signal a top. [3]",
          "source_ids" => [3],
          "financial_disclaimer" => false
        })

      rendered = Citations.render(content, registry())

      assert rendered =~
               "Social volume can signal a top. [Academy: Getting Started for Traders](https://s/academy/3)"

      # and it renders as exactly one anchor pointing at the real url
      html = Earmark.as_html!(rendered)
      assert html =~ ~s(href="https://s/academy/3")
    end

    test "leaves an unknown numeric token untouched" do
      content =
        json(%{"answer" => "See step [9].", "source_ids" => [], "financial_disclaimer" => false})

      assert Citations.render(content, registry()) =~ "See step [9]."
    end

    test "expands every occurrence of a cited id" do
      content =
        json(%{
          "answer" => "A [1] then B [1].",
          "source_ids" => [1],
          "financial_disclaimer" => false
        })

      rendered = Citations.render(content, registry())
      # both inline tokens become the full prefixed link (the Sources bullet uses
      # the bare-label form, so counting the prefixed form isolates the inline ones)
      assert length(Regex.scan(~r/\[FAQ: What is MVRV\?\]\(https:\/\/s\/faq\/1\)/, rendered)) == 2
    end
  end

  describe "render/2 grouped Sources section" do
    test "groups cited sources under Insight / Academy / FAQ headers, in that order" do
      content =
        json(%{
          "answer" => "Intro [1]. Body [2]. More [3].",
          "source_ids" => [1, 2, 3],
          "financial_disclaimer" => false
        })

      rendered = Citations.render(content, registry())

      assert rendered =~ "### Sources"

      assert rendered =~
               "**Insight:**\n- [Understanding Market Expectations](https://s/insight/2)"

      assert rendered =~ "**Academy:**\n- [Getting Started for Traders](https://s/academy/3)"
      assert rendered =~ "**FAQ:**\n- [What is MVRV?](https://s/faq/1)"

      # group order is Insight, then Academy, then FAQ
      assert pos(rendered, "**Insight:**") < pos(rendered, "**Academy:**")
      assert pos(rendered, "**Academy:**") < pos(rendered, "**FAQ:**")
    end

    test "lists only cited sources and omits empty groups" do
      content =
        json(%{
          "answer" => "Only this [3].",
          "source_ids" => [3],
          "financial_disclaimer" => false
        })

      rendered = Citations.render(content, registry())

      assert rendered =~ "**Academy:**"
      refute rendered =~ "**FAQ:**"
      refute rendered =~ "**Insight:**"
    end

    test "a source cited inline still appears in Sources even if missing from source_ids" do
      content =
        json(%{
          "answer" => "Cited inline [2].",
          "source_ids" => [],
          "financial_disclaimer" => false
        })

      rendered = Citations.render(content, registry())

      assert rendered =~
               "**Insight:**\n- [Understanding Market Expectations](https://s/insight/2)"
    end

    test "a source in source_ids but not cited inline still appears in Sources" do
      content =
        json(%{
          "answer" => "No inline tokens here.",
          "source_ids" => [1],
          "financial_disclaimer" => false
        })

      rendered = Citations.render(content, registry())
      assert rendered =~ "**FAQ:**\n- [What is MVRV?](https://s/faq/1)"
    end

    test "insight bullet shows the publication date sentinel; inline link does not" do
      registry = [
        %{
          id: 1,
          source: :insight,
          prefix: "Insight",
          label: "BTC outlook",
          url: "https://s/insight/1",
          published_on: ~D[2026-01-02]
        }
      ]

      content =
        json(%{
          "answer" => "BTC looks volatile. [1]",
          "source_ids" => [1],
          "financial_disclaimer" => false
        })

      rendered = Citations.render(content, registry)

      assert rendered =~ "**Insight:**\n- [BTC outlook](https://s/insight/1) {{date:2026-01-02}}"
      # the inline citation stays a plain link — the date only decorates Sources
      assert rendered =~ "BTC looks volatile. [Insight: BTC outlook](https://s/insight/1)\n"
    end

    test "no Sources section when nothing was cited" do
      content =
        json(%{"answer" => "Plain answer.", "source_ids" => [], "financial_disclaimer" => false})

      refute Citations.render(content, registry()) =~ "Sources"
    end
  end

  describe "render/2 disclaimer" do
    test "appends the disclaimer after Sources when financial_disclaimer is true" do
      content =
        json(%{"answer" => "Tops [3].", "source_ids" => [3], "financial_disclaimer" => true})

      rendered = Citations.render(content, registry())

      assert rendered =~ "*Disclaimer:"
      assert pos(rendered, "### Sources") < pos(rendered, "*Disclaimer:")
    end

    test "omits the disclaimer when financial_disclaimer is false" do
      content =
        json(%{"answer" => "Tops [3].", "source_ids" => [3], "financial_disclaimer" => false})

      refute Citations.render(content, registry()) =~ "Disclaimer:"
    end
  end

  describe "render/2 fallback" do
    test "returns the raw content unchanged when it is not valid JSON" do
      assert Citations.render("not json at all", registry()) == "not json at all"
    end

    test "treats malformed link delimiters in a label as inert text" do
      reg = [
        %{
          id: 1,
          source: :academy,
          prefix: "Academy",
          label: "Evil](https://phish.example)",
          url: "https://s/academy/1"
        }
      ]

      content =
        json(%{"answer" => "Claim [1].", "source_ids" => [1], "financial_disclaimer" => false})

      html = content |> Citations.render(reg) |> Earmark.as_html!()

      assert html =~ ~s(href="https://s/academy/1")
      refute html =~ ~s(href="https://phish.example")
    end

    test "a url's markdown delimiters are percent-encoded so it can't break out of the link" do
      reg = [
        %{
          id: 1,
          source: :academy,
          prefix: "Academy",
          label: "A",
          url: "https://s/academy/1)](https://phish.example"
        }
      ]

      content =
        json(%{"answer" => "Claim [1].", "source_ids" => [1], "financial_disclaimer" => false})

      rendered = Citations.render(content, reg)

      # the url's `)` and `(` are encoded, so the raw `)](` breakout sequence that
      # would close the link early and inject a second target is gone.
      assert rendered =~ "%29"
      assert rendered =~ "%28"
      refute rendered =~ ")]("
    end

    test "a non-http(s) scheme is neutralised to '#'" do
      reg = [
        %{id: 1, source: :academy, prefix: "Academy", label: "A", url: "javascript:alert(1)"}
      ]

      content =
        json(%{"answer" => "Claim [1].", "source_ids" => [1], "financial_disclaimer" => false})

      rendered = Citations.render(content, reg)

      refute rendered =~ "javascript:"
      assert rendered =~ "(#)"
    end
  end

  describe "response_format/0" do
    test "is a strict json_schema requiring answer, source_ids and financial_disclaimer" do
      rf = Citations.response_format()

      assert rf["type"] == "json_schema"
      assert rf["json_schema"]["strict"] == true
      schema = rf["json_schema"]["schema"]
      assert schema["additionalProperties"] == false
      assert Enum.sort(schema["required"]) == ["answer", "financial_disclaimer", "source_ids"]
    end
  end

  defp pos(haystack, needle) do
    [{start, _}] = Regex.run(~r/#{Regex.escape(needle)}/, haystack, return: :index)
    start
  end
end
