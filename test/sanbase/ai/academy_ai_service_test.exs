defmodule Sanbase.AI.AcademyAIServiceTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.AI.AcademyAIService
  alias Sanbase.Chat
  alias Sanbase.Knowledge.{AcademyArticle, AcademyArticleChunk}
  alias Sanbase.Repo

  @embedding_size 1536

  setup do
    user = insert(:user)

    {:ok, chat} =
      Chat.create_chat(%{
        title: "Academy Test Chat",
        user_id: user.id,
        type: "academy_qa"
      })

    # Add some chat history
    {:ok, _msg1} = Chat.add_message_to_chat(chat.id, "What is DeFi?", :user, %{})

    {:ok, _msg2} =
      Chat.add_message_to_chat(
        chat.id,
        "DeFi stands for Decentralized Finance...",
        :assistant,
        %{}
      )

    %{
      user: user,
      chat: chat
    }
  end

  describe "semantic_search/2" do
    test "returns the matching academy chunks ordered by relevance, without LLM synthesis" do
      article =
        insert_article(
          title: "MVRV Guide",
          academy_url: "https://academy.santiment.net/metrics/mvrv/",
          github_path: "src/metrics/mvrv.md"
        )

      # The relevant chunk shares the query embedding (similarity ~1); the other
      # is orthogonal (similarity ~0), so vector search ranks the relevant one first.
      insert_chunk(article,
        chunk_index: 0,
        heading: "MVRV",
        content: "MVRV compares market value to realized value.",
        embedding: unit_vector(0)
      )

      insert_chunk(article,
        chunk_index: 1,
        heading: "Unrelated",
        content: "Something completely unrelated to the query.",
        embedding: unit_vector(5)
      )

      with_query_embedding(unit_vector(0), fn ->
        assert {:ok, [first, second]} = AcademyAIService.semantic_search("what is mvrv", top_k: 5)

        assert first.title == "MVRV Guide"
        assert first.url == "https://academy.santiment.net/metrics/mvrv/"
        assert first.heading == "MVRV"
        assert first.chunk == "MVRV compares market value to realized value."
        assert is_number(first.similarity)

        # The orthogonal chunk is still returned but ranks lower.
        assert second.heading == "Unrelated"
        assert first.similarity >= second.similarity
      end)
    end

    test "respects the :top_k option" do
      article = insert_article()

      for index <- 0..4 do
        insert_chunk(article,
          chunk_index: index,
          content: "Chunk #{index}",
          embedding: unit_vector(index)
        )
      end

      with_query_embedding(unit_vector(0), fn ->
        assert {:ok, results} = AcademyAIService.semantic_search("query", top_k: 2)
        assert length(results) == 2
      end)
    end

    test "returns at most 2 chunks per article while other articles can fill the slots" do
      long_page =
        insert_article(
          title: "Long",
          academy_url: "https://academy.santiment.net/long/",
          github_path: "long.md"
        )

      other =
        insert_article(
          title: "Other",
          academy_url: "https://academy.santiment.net/other/",
          github_path: "other.md"
        )

      # Four near-identical chunks of the long page all beat the other page's chunk.
      for index <- 0..3 do
        insert_chunk(long_page,
          chunk_index: index,
          content: "Long chunk #{index}",
          embedding: near_vector(0, 1, 0.01 * index)
        )
      end

      insert_chunk(other,
        chunk_index: 0,
        content: "Other chunk",
        embedding: near_vector(0, 1, 0.5)
      )

      with_query_embedding(unit_vector(0), fn ->
        assert {:ok, results} = AcademyAIService.semantic_search("query", top_k: 3)
        assert Enum.map(results, & &1.title) == ["Long", "Long", "Other"]

        assert {:ok, uncapped} =
                 AcademyAIService.semantic_search("query", top_k: 3, max_chunks_per_article: nil)

        assert Enum.map(uncapped, & &1.title) == ["Long", "Long", "Long"]
      end)
    end

    test "clamps :top_k to 1..50" do
      article = insert_article()
      insert_chunk(article, chunk_index: 0, content: "Only chunk", embedding: unit_vector(0))

      with_query_embedding(unit_vector(0), fn ->
        assert {:ok, [_]} = AcademyAIService.semantic_search("query", top_k: -5)
      end)
    end

    test "returns an empty list when there are no academy chunks" do
      with_query_embedding(unit_vector(0), fn ->
        assert {:ok, []} = AcademyAIService.semantic_search("query")
      end)
    end
  end

  describe "answer/2" do
    setup do
      article =
        insert_article(
          title: "MVRV",
          academy_url: "https://academy.santiment.net/metrics/mvrv/",
          github_path: "src/metrics/mvrv.md"
        )

      insert_chunk(article,
        chunk_index: 0,
        heading: "MVRV",
        content: "MVRV compares market value to realized value.",
        embedding: unit_vector(0)
      )

      :ok
    end

    test "searches the question as-is when there is no history" do
      parent = self()

      answer_mocks(parent, fn :rewrite -> flunk("no rewrite without history") end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, %{search_query: "What is MVRV?", sources: [%{"title" => "MVRV"}]}} =
                 AcademyAIService.answer("What is MVRV?", include_suggestions: false)

        assert_received {:embedded, ["What is MVRV?"]}
        assert_received {:prompt, :answer, answer_prompt}
        refute answer_prompt =~ "Interpreted as"
      end)
    end

    test "rewrites a follow-up into a standalone search query using the history" do
      parent = self()

      history = [
        %{role: "user", content: "What is MVRV?"},
        %{role: "assistant", content: "A ratio [1]."}
      ]

      answer_mocks(parent, fn :rewrite -> {:ok, "How is MVRV calculated?"} end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, %{search_query: "How is MVRV calculated?"}} =
                 AcademyAIService.answer("How is it calculated?",
                   chat_history: history,
                   include_suggestions: false
                 )

        assert_received {:embedded, ["How is MVRV calculated?"]}
        assert_received {:prompt, :rewrite, rewrite_prompt}
        assert rewrite_prompt =~ "User: What is MVRV?"
        assert rewrite_prompt =~ "Latest question: How is it calculated?"

        # The answer prompt keeps the user's own question plus the rewrite.
        assert_received {:prompt, :answer, answer_prompt}
        assert answer_prompt =~ "Question: How is it calculated?"
        assert answer_prompt =~ "(Interpreted as: How is MVRV calculated?)"
      end)
    end

    test "searches the raw question when the rewrite fails" do
      history = [%{role: "user", content: "What is MVRV?"}]

      answer_mocks(self(), fn :rewrite -> {:error, "timeout"} end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, %{search_query: "How is it calculated?"}} =
                 AcademyAIService.answer("How is it calculated?",
                   chat_history: history,
                   include_suggestions: false
                 )
      end)
    end
  end

  describe "generate_local_response/4 history" do
    test "sends the latest messages, without the current question", %{chat: chat} do
      # The setup chat has 2 messages; add 10 more turns, then the current question.
      for i <- 1..10 do
        add_message_at(chat.id, "question #{i}", :user, 2 * i)
        add_message_at(chat.id, "answer #{i}", :assistant, 2 * i + 1)
      end

      add_message_at(chat.id, "How is it calculated?", :user, 100)

      parent = self()

      answer_mocks(parent, fn :rewrite -> {:ok, "rewritten"} end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:ok, _} =
          AcademyAIService.generate_local_response("How is it calculated?", chat.id, nil, false)

        assert_received {:prompt, :answer, prompt}
        [_, history] = String.split(prompt, "Recent conversation history:")
        assert history =~ "answer 10"
        assert history =~ "question 8"
        refute history =~ "What is DeFi?"
        refute history =~ "User: How is it calculated?"
      end)
    end
  end

  # Helpers

  # Messages inserted in one test share a timestamp (second precision), so each
  # gets an explicit one, `seconds` after the setup messages.
  defp add_message_at(chat_id, content, role, seconds) do
    {:ok, message} = Chat.add_message_to_chat(chat_id, content, role, %{})

    message
    |> Ecto.Changeset.change(
      inserted_at:
        NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.add(seconds)
    )
    |> Repo.update!()
  end

  # Mocks the embedding (reporting the embedded texts) and `Question.ask/2`:
  # the rewrite call is answered by `rewrite`, the answer call cites source [1].
  defp answer_mocks(parent, rewrite) do
    Sanbase.Mock.prepare_mock(Sanbase.AI.Embedding, :generate_embeddings, fn texts, _size ->
      send(parent, {:embedded, texts})
      {:ok, [unit_vector(0)]}
    end)
    |> Sanbase.Mock.prepare_mock(Sanbase.OpenAI.Question, :ask, fn prompt, opts ->
      case opts[:generation_name] do
        "academy.qa.rewrite" ->
          send(parent, {:prompt, :rewrite, prompt})
          rewrite.(:rewrite)

        _ ->
          send(parent, {:prompt, :answer, prompt})
          {:ok, "MVRV is a ratio [1]."}
      end
    end)
  end

  defp insert_article(attrs \\ []) do
    defaults = %{
      title: "Academy Article",
      academy_url: "https://academy.santiment.net/article/",
      github_path: "src/article.md",
      content_sha: "sha-#{System.unique_integer([:positive])}",
      is_stale: false
    }

    %AcademyArticle{}
    |> AcademyArticle.changeset(Map.merge(defaults, Map.new(attrs)))
    |> Repo.insert!()
  end

  defp insert_chunk(article, attrs) do
    attrs = Map.new(attrs)

    %AcademyArticleChunk{}
    |> AcademyArticleChunk.changeset(%{
      article_id: article.id,
      chunk_index: Map.fetch!(attrs, :chunk_index),
      heading: Map.get(attrs, :heading),
      content: Map.fetch!(attrs, :content),
      embedding: Map.fetch!(attrs, :embedding),
      is_stale: false
    })
    |> Repo.insert!()
  end

  # A unit vector with 1.0 at `index` and zeros elsewhere. Two unit vectors at
  # the same index are identical (cosine similarity 1); at different indices
  # they are orthogonal (cosine similarity 0).
  # Unit vector mostly along `main` with a `weight` component along `other`.
  defp near_vector(main, other, weight) do
    norm = :math.sqrt(1 + weight * weight)

    List.duplicate(0.0, @embedding_size)
    |> List.replace_at(main, 1 / norm)
    |> List.replace_at(other, weight / norm)
  end

  defp unit_vector(index) do
    List.duplicate(0.0, @embedding_size) |> List.replace_at(index, 1.0)
  end

  defp with_query_embedding(embedding, fun) do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.AI.Embedding.generate_embeddings/2,
      {:ok, [embedding]}
    )
    |> Sanbase.Mock.run_with_mocks(fun)
  end
end
