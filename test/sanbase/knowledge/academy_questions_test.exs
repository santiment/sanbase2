defmodule Sanbase.Knowledge.AcademyQuestionsTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Knowledge.{Academy, AcademyArticle, AcademyArticleChunk, AcademyQuestions}
  alias Sanbase.Repo

  @embedding_size 1536

  describe "suggest/2" do
    setup do
      mcp =
        insert_article("MCP Connector", "/mcp-connector/",
          questions: [
            "How do I connect the Santiment MCP connector to Claude?",
            "Which tools does the MCP connector expose?",
            "What are the MCP connector rate limits?"
          ],
          headings: ["Setup in Claude Desktop"]
        )

      inflow =
        insert_article("Exchange Funds Flow", "/metrics/exchange-funds-flow/",
          questions: ["What does exchange inflow measure?"],
          headings: ["Exchange Inflow"]
        )

      dsproxy =
        insert_article("DSProxy", "/labels/dsproxy/",
          questions: ["What is the DSProxy label fqn?"],
          headings: ["Smart wallet"]
        )

      %{index: AcademyQuestions.build_index(), mcp: mcp, inflow: inflow, dsproxy: dsproxy}
    end

    test "matches a partial last word", %{index: index} do
      suggestions = AcademyQuestions.suggest("mcp conn", index: index)

      assert suggestions != []
      assert Enum.all?(suggestions, &(&1.question =~ ~r/MCP conn/))
    end

    test "returns title, question and url", %{index: index} do
      assert [suggestion | _] = AcademyQuestions.suggest("exchange inflow", index: index)

      assert suggestion == %{
               title: "Exchange Funds Flow",
               question: "What does exchange inflow measure?",
               url: "https://academy.santiment.net/metrics/exchange-funds-flow/"
             }
    end

    test "matches close misspellings", %{index: index} do
      assert [%{url: "https://academy.santiment.net/metrics/exchange-funds-flow/"} | _] =
               AcademyQuestions.suggest("exchnage inflow", index: index)
    end

    test "matches words of the article title and section headings", %{index: index} do
      # "smart wallet" appears only in a DSProxy heading, not in its question.
      assert [%{url: "https://academy.santiment.net/labels/dsproxy/"}] =
               AcademyQuestions.suggest("smart wallet", index: index)
    end

    test "ignores stopwords", %{index: index} do
      assert [%{url: "https://academy.santiment.net/labels/dsproxy/"}] =
               AcademyQuestions.suggest("what is the dsproxy", index: index)
    end

    test "returns at most two questions per article", %{index: index} do
      suggestions = AcademyQuestions.suggest("mcp", index: index)

      assert length(suggestions) == 2
      assert Enum.all?(suggestions, &(&1.url == "https://academy.santiment.net/mcp-connector/"))
    end

    test "falls back to all but one word when nothing matches every word", %{index: index} do
      assert [%{url: "https://academy.santiment.net/labels/dsproxy/"}] =
               AcademyQuestions.suggest("dsproxy zebra", index: index)
    end

    test "returns nothing for unrelated or empty queries", %{index: index} do
      assert AcademyQuestions.suggest("zebra", index: index) == []
      assert AcademyQuestions.suggest("", index: index) == []
      assert AcademyQuestions.suggest("?!", index: index) == []
    end

    test "skips stale articles" do
      article = insert_article("Stale Page", "/stale/", questions: ["What is a zebra chart?"])
      article |> Ecto.Changeset.change(is_stale: true) |> Repo.update!()

      assert AcademyQuestions.suggest("zebra", index: AcademyQuestions.build_index()) == []
    end
  end

  describe "generate/1" do
    test "by default generates only for articles without questions" do
      new = insert_article("New Page", "/new/", headings: ["Intro"])
      old = insert_article("Old Page", "/old/", questions: ["What is old?"])

      result =
        AcademyQuestions.generate(
          generate_fun: fn input -> {:ok, ["What is #{input.title}?"]} end,
          concurrency: 1
        )

      assert result == %{generated: 1, skipped: 0, failed: []}
      assert Repo.get!(AcademyArticle, new.id).suggested_questions == ["What is New Page?"]
      assert Repo.get!(AcademyArticle, new.id).questions_content_sha == new.content_sha
      assert Repo.get!(AcademyArticle, old.id).suggested_questions == ["What is old?"]
    end

    test "passes the article text and headings to the generator" do
      insert_article("MVRV", "/metrics/mvrv/", headings: ["Definition"], content: "MVRV body.")
      parent = self()

      AcademyQuestions.generate(
        generate_fun: fn input ->
          send(parent, {:input, input})
          {:ok, ["What is MVRV?"]}
        end
      )

      assert_received {:input, input}
      assert input.title == "MVRV"
      assert input.url == "https://academy.santiment.net/metrics/mvrv/"
      assert input.headings == ["Definition"]
      assert input.text =~ "MVRV body."
    end

    test "stale: true also regenerates articles whose content changed" do
      changed = insert_article("Changed", "/changed/", questions: ["What was it?"])
      changed |> Ecto.Changeset.change(content_sha: "new-sha") |> Repo.update!()
      _fresh = insert_article("Fresh", "/fresh/", questions: ["What is fresh?"])

      result =
        AcademyQuestions.generate(stale: true, generate_fun: fn _ -> {:ok, ["What now?"]} end)

      assert result.generated == 1
      assert Repo.get!(AcademyArticle, changed.id).suggested_questions == ["What now?"]
      assert Repo.get!(AcademyArticle, changed.id).questions_content_sha == "new-sha"
    end

    test "force: true regenerates every article" do
      insert_article("One", "/one/", questions: ["What is one?"])
      insert_article("Two", "/two/")

      assert %{generated: 2} =
               AcademyQuestions.generate(force: true, generate_fun: fn _ -> {:ok, ["Q?"]} end)
    end

    test "dry_run returns the questions without storing them" do
      article = insert_article("Dry", "/dry/")

      result = AcademyQuestions.generate(dry_run: true, generate_fun: fn _ -> {:ok, ["Why?"]} end)

      assert result.questions == [{"Dry", ["Why?"]}]
      assert Repo.get!(AcademyArticle, article.id).suggested_questions == []
    end

    test "records failures and skips articles without chunks" do
      failing = insert_article("Failing", "/failing/")
      insert_article("Empty", "/empty/", content: nil)

      result = AcademyQuestions.generate(generate_fun: fn _ -> {:error, :boom} end)

      assert result == %{generated: 0, skipped: 1, failed: [{failing.id, :boom}]}
    end
  end

  describe "parse_questions/1" do
    test "keeps valid, distinct questions, at most five" do
      content =
        Jason.encode!(%{
          "questions" => [
            "What is MVRV?",
            "what is mvrv?",
            "Not a question",
            "Short?",
            42,
            "How  is   MVRV computed?",
            "Why a?" <> String.duplicate("x", 200),
            "Which MVRV metrics exist?",
            "When is MVRV high?",
            "Where is MVRV shown?",
            "Who uses MVRV?"
          ]
        })

      assert AcademyQuestions.parse_questions(content) ==
               {:ok,
                [
                  "What is MVRV?",
                  "How is MVRV computed?",
                  "Which MVRV metrics exist?",
                  "When is MVRV high?",
                  "Where is MVRV shown?"
                ]}
    end

    test "rejects malformed output" do
      assert {:error, {:invalid_response, _}} = AcademyQuestions.parse_questions("not json")

      assert {:error, :no_valid_questions} =
               AcademyQuestions.parse_questions(~s({"questions": []}))
    end
  end

  describe "reindex" do
    test "keeps stored questions for articles that are re-inserted" do
      path = "src/content/docs/metrics/mvrv/index.mdx"

      article =
        insert_article("MVRV", "/metrics/mvrv/",
          github_path: path,
          questions: ["What is MVRV?"]
        )

      markdown = "# MVRV\n\n" <> String.duplicate("MVRV compares market and realized value. ", 30)

      Sanbase.Mock.prepare_mock(Req, :get, fn url, _opts ->
        cond do
          url =~ "/git/trees/" ->
            {:ok,
             %Req.Response{
               status: 200,
               body: %{"tree" => [%{"path" => path, "type" => "blob", "sha" => "new-sha"}]}
             }}

          url =~ "/repos/santiment/sanpy/" ->
            {:ok, %Req.Response{status: 200, body: github_file("# Sanpy\n\nPython client.")}}

          url =~ "/contents/" ->
            {:ok, %Req.Response{status: 200, body: github_file(markdown)}}
        end
      end)
      |> Sanbase.Mock.prepare_mock(Sanbase.AI.Embedding, :generate_embeddings, fn texts, size ->
        {:ok, Enum.map(texts, fn _ -> List.duplicate(0.1, size) end)}
      end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert :ok = Academy.reindex_academy(force: true)
      end)

      reindexed = Repo.get_by!(AcademyArticle, github_path: path)
      assert reindexed.content_sha == "new-sha"
      assert reindexed.suggested_questions == ["What is MVRV?"]
      # Kept from before the reindex, so `generate(stale: true)` picks the article up.
      assert reindexed.questions_content_sha == article.content_sha
    end
  end

  defp github_file(content), do: %{"content" => Base.encode64(content), "encoding" => "base64"}

  defp insert_article(title, path, opts \\ []) do
    article =
      %AcademyArticle{}
      |> AcademyArticle.changeset(%{
        title: title,
        academy_url: "https://academy.santiment.net" <> path,
        github_path: Keyword.get(opts, :github_path, "src/content/docs#{path}index.mdx"),
        content_sha: "sha-#{System.unique_integer([:positive])}",
        is_stale: false
      })
      |> Repo.insert!()

    article =
      case Keyword.get(opts, :questions) do
        nil -> article
        questions -> article |> AcademyArticle.questions_changeset(questions) |> Repo.update!()
      end

    headings = Keyword.get(opts, :headings, [nil])
    content = Keyword.get(opts, :content, "#{title} body text.")

    if content do
      headings
      |> Enum.with_index()
      |> Enum.each(fn {heading, i} ->
        %AcademyArticleChunk{}
        |> AcademyArticleChunk.changeset(%{
          article_id: article.id,
          chunk_index: i,
          heading: heading,
          content: content,
          embedding: List.duplicate(0.0, @embedding_size) |> List.replace_at(0, 1.0),
          is_stale: false
        })
        |> Repo.insert!()
      end)
    end

    article
  end
end
