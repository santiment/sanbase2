defmodule Sanbase.MCP.Knowledge.ToolsTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Anubis.Server.Frame
  alias Anubis.Server.Response
  alias Sanbase.Knowledge.{AcademyArticle, AcademyArticleChunk, Faq, FaqEntry, QueryPlan}
  alias Sanbase.MCP.Knowledge
  alias Sanbase.Repo

  @moduletag capture_log: true

  # Every entry and every query share this embedding, so similarity is always 1.0.
  @embedding List.duplicate(0.1, 1536)

  setup do
    user = insert(:user, email: "support@santiment.net")
    %{user: user, frame: Frame.new(%{current_user: user})}
  end

  defp insert_faq(attrs, status \\ :published) do
    %FaqEntry{status: status, embedding: Pgvector.new(@embedding)}
    |> FaqEntry.changeset(attrs)
    |> Repo.insert!()
  end

  # Embeddings always return @embedding; the query plan skips its LLM call.
  defp with_mocks(fun) do
    Sanbase.Mock.prepare_mock2(&Sanbase.AI.Embedding.generate_embeddings/2, {:ok, [@embedding]})
    |> Sanbase.Mock.prepare_mock(QueryPlan, :build, fn question, _opts ->
      %QueryPlan{semantic_query: question}
    end)
    |> Sanbase.Mock.run_with_mocks(fun)
  end

  defp call(tool, params, frame) do
    {:reply, %Response{} = response, _frame} = tool.execute(params, frame)
    protocol = Response.to_protocol(response)
    [%{"text" => text}] = protocol["content"]

    if protocol["isError"], do: {:error, text}, else: {:ok, Jason.decode!(text)}
  end

  describe "search_knowledge" do
    test "returns numbered excerpts of published entries only", %{frame: frame} do
      published = insert_faq(%{"question" => "What is MVRV?", "answer_markdown" => "A ratio."})
      draft = insert_faq(%{"question" => "Draft MVRV?", "answer_markdown" => "Unsure."}, :draft)

      with_mocks(fn ->
        assert {:ok, result} =
                 call(
                   Knowledge.SearchKnowledgeTool,
                   %{question: "What is MVRV?", sources: ["faq"]},
                   frame
                 )

        assert [excerpt] = result["excerpts"]

        assert %{"n" => 1, "type" => "faq", "is_full_text" => true, "text" => "A ratio."} =
                 excerpt

        assert excerpt["id"] == published.id
        assert result["plan_restrictions"] =~ "SanAPI PRO"
        refute Map.has_key?(result, "drafts")

        assert {:ok, result} =
                 call(
                   Knowledge.SearchKnowledgeTool,
                   %{
                     question: "What is MVRV?",
                     sources: ["faq"],
                     include_drafts: true,
                     include_plan_restrictions: false
                   },
                   frame
                 )

        assert [%{"id" => draft_id, "status" => "draft"}] = result["drafts"]
        assert draft_id == draft.id
        refute Map.has_key?(result, "plan_restrictions")
        assert Enum.map(result["excerpts"], & &1["id"]) == [published.id]
      end)

      assert [%{question_type: "mcp_search"} | _] =
               Sanbase.Knowledge.QuestionAnswerLog.list_entries()
    end
  end

  describe "fetch_entry" do
    test "returns a full FAQ entry, drafts included", %{frame: frame} do
      draft =
        insert_faq(
          %{"question" => "Q?", "answer_markdown" => "A.", "internal_notes" => "n"},
          :draft
        )

      assert {:ok, %{"type" => "faq", "status" => "draft", "internal_notes" => "n"} = entry} =
               call(Knowledge.FetchEntryTool, %{type: "faq", id: draft.id}, frame)

      assert entry["admin_url"] =~ "/admin/faq/#{draft.id}"
    end

    test "returns the full text of an academy article", %{frame: frame} do
      article =
        %AcademyArticle{}
        |> AcademyArticle.changeset(%{
          github_path: "src/docs/mvrv.md",
          academy_url: "https://academy.santiment.net/mvrv",
          title: "MVRV",
          content_sha: "sha"
        })
        |> Repo.insert!()

      for {content, index} <- Enum.with_index(["First part of the article.", "Second part."]) do
        %AcademyArticleChunk{}
        |> AcademyArticleChunk.changeset(%{
          article_id: article.id,
          chunk_index: index,
          content: content,
          embedding: @embedding
        })
        |> Repo.insert!()
      end

      assert {:ok, %{"type" => "academy", "title" => "MVRV", "text" => text}} =
               call(
                 Knowledge.FetchEntryTool,
                 %{type: "academy", id: to_string(article.id)},
                 frame
               )

      assert text =~ "First part of the article."
      assert text =~ "Second part."
    end

    test "returns published insights and hides unpublished ones", %{frame: frame} do
      post = insert(:published_post, text: "Full insight text", is_paywall_required: true)
      draft_post = insert(:post)

      assert {:ok, %{"type" => "insight", "text" => "Full insight text", "paywalled" => true}} =
               call(Knowledge.FetchEntryTool, %{type: "insight", id: post.id}, frame)

      assert {:error, message} =
               call(Knowledge.FetchEntryTool, %{type: "insight", id: draft_post.id}, frame)

      assert message =~ "No insight entry"
    end
  end

  describe "create_faq_draft" do
    test "creates a draft attributed to the caller", %{frame: frame, user: user} do
      params = %{
        question: "How do I rotate my API key?",
        answer_markdown: "Open Account settings and generate a new key.",
        tags: ["api"],
        internal_notes: "From a support chat; confirmed by the backend team."
      }

      assert {:ok, %{"created" => true, "entry" => entry}} =
               with_mocks(fn -> call(Knowledge.CreateFaqDraftTool, params, frame) end)

      assert %{"status" => "draft", "tags" => ["api"]} = entry
      assert entry["created_by"] == user.email

      {:ok, saved} = Faq.get_entry(entry["id"])
      assert saved.origin == :mcp
      assert saved.created_by_id == user.id
    end
  end

  describe "update_faq_draft" do
    test "updates drafts and refuses published entries", %{frame: frame} do
      draft = insert_faq(%{"question" => "Q?", "answer_markdown" => "A."}, :draft)
      published = insert_faq(%{"question" => "Live?", "answer_markdown" => "Yes."})

      assert {:ok, %{"updated" => true, "entry" => %{"answer_markdown" => "Better."}}} =
               with_mocks(fn ->
                 call(
                   Knowledge.UpdateFaqDraftTool,
                   %{id: draft.id, answer_markdown: "Better."},
                   frame
                 )
               end)

      assert {:error, message} =
               call(
                 Knowledge.UpdateFaqDraftTool,
                 %{id: published.id, answer_markdown: "No."},
                 frame
               )

      assert message =~ "already published"
    end
  end

  test "answer_question returns the generated answer and logs it", %{frame: frame} do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.Knowledge.answer_question/2,
      {:ok, "Generated answer [1]", %QueryPlan{semantic_query: "q"}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert {:ok, %{"answer" => "Generated answer [1]"}} =
               call(Knowledge.AnswerQuestionTool, %{question: "What is MVRV?"}, frame)
    end)

    assert [%{question_type: "mcp_answer", is_successful: true}] =
             Sanbase.Knowledge.QuestionAnswerLog.list_entries()
  end

  test "the server refuses non-team users even past the plug" do
    outsider = insert(:user, email: "someone@gmail.com")
    frame = Frame.new(%{current_user: outsider})

    assert {:error, %Anubis.MCP.Error{}, _frame} =
             Knowledge.Server.handle_request(%{"method" => "tools/list"}, frame)
  end
end
