defmodule Sanbase.Knowledge.FaqDraftsTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Knowledge.{Faq, FaqEntry, FaqSync}
  alias Sanbase.Repo

  # Every entry and every query share this embedding, so similarity search
  # returns all entries with similarity 1.0 and only the filters decide.
  @embedding List.duplicate(0.1, 1536)

  setup do
    %{user: insert(:user)}
  end

  # Creating or updating an entry embeds it; keep that off the network.
  defp with_embeddings(fun) do
    Sanbase.Mock.prepare_mock2(&Sanbase.AI.Embedding.generate_embeddings/2, {:ok, [@embedding]})
    |> Sanbase.Mock.run_with_mocks(fun)
  end

  defp insert_faq(attrs, status \\ :published) do
    %FaqEntry{status: status, embedding: Pgvector.new(@embedding)}
    |> FaqEntry.changeset(attrs)
    |> Repo.insert!()
  end

  defp create_draft(user, attrs, opts \\ []) do
    with_embeddings(fn -> Faq.create_draft(user, attrs, opts) end)
  end

  describe "create_draft/3" do
    test "stores an embedded, unreviewed draft attributed to the user", %{user: user} do
      assert {:ok, entry} =
               create_draft(user, %{
                 question: "How do I reset my API key?",
                 answer_markdown: "Go to Account settings.",
                 internal_notes: "Asked by a user on Discord",
                 tags: ["api"]
               })

      assert entry.status == :draft
      assert entry.origin == :mcp
      assert entry.created_by_id == user.id
      assert entry.internal_notes == "Asked by a user on Discord"
      assert Enum.map(entry.tags, & &1.name) == ["api"]
      # Embedded before saving, so an immediate duplicate check sees it.
      assert %Pgvector{} = Repo.get!(FaqEntry, entry.id).embedding
    end

    test "returns near-duplicates instead of saving, unless forced", %{user: user} do
      existing = insert_faq(%{"question" => "What is MVRV?", "answer_markdown" => "A ratio."})
      attrs = %{question: "What does MVRV mean?", answer_markdown: "It is a ratio."}

      assert {:duplicates, [%{id: id}]} = create_draft(user, attrs)
      assert id == existing.id
      assert Faq.count_entries(status: :draft) == 0

      assert {:ok, %FaqEntry{}} = create_draft(user, attrs, force: true)
    end

    test "a rejected draft's question can be drafted again", %{user: user} do
      {:ok, rejected} = create_draft(user, %{question: "Q?", answer_markdown: "Wrong."})
      {:ok, _} = Faq.delete_entry(rejected)

      assert {:ok, %FaqEntry{}} = create_draft(user, %{question: "Q?", answer_markdown: "Right."})
    end
  end

  describe "publish/2" do
    test "publishes a draft and records the reviewer", %{user: user} do
      reviewer = insert(:user)
      {:ok, draft} = create_draft(user, %{question: "Q?", answer_markdown: "A."})

      assert {:ok, entry} = Faq.publish(draft, reviewer)
      assert entry.status == :published
      assert entry.reviewed_by_id == reviewer.id
      assert %NaiveDateTime{} = entry.reviewed_at

      assert {:error, :not_a_draft} = Faq.publish(entry, reviewer)
    end

    test "refuses a draft edited after the reviewer loaded it", %{user: user} do
      reviewer = insert(:user)
      {:ok, seen} = create_draft(user, %{question: "Q?", answer_markdown: "Reviewed answer."})

      {:ok, _} = with_embeddings(fn -> Faq.update_draft(seen, %{answer_markdown: "Unseen."}) end)

      assert {:error, :changed} = Faq.publish(seen, reviewer)
      assert Repo.get!(FaqEntry, seen.id).status == :draft

      assert {:ok, %FaqEntry{answer_markdown: "Unseen."}} =
               Faq.publish(Repo.get!(FaqEntry, seen.id), reviewer)
    end
  end

  describe "update_draft/2" do
    test "refuses an entry published since it was loaded", %{user: user} do
      {:ok, draft} = create_draft(user, %{question: "Q?", answer_markdown: "A."})
      {:ok, _} = Faq.publish(draft, insert(:user))

      # `draft` still says :draft in memory; the database decides.
      assert {:error, :not_a_draft} =
               with_embeddings(fn -> Faq.update_draft(draft, %{answer_markdown: "No."}) end)

      assert Repo.get!(FaqEntry, draft.id).answer_markdown == "A."
    end
  end

  describe "drafts stay out of every read path" do
    setup do
      published = insert_faq(%{"question" => "Published?", "answer_markdown" => "Yes."})
      draft = insert_faq(%{"question" => "Draft?", "answer_markdown" => "Maybe."}, :draft)
      %{published: published, draft: draft}
    end

    test "similarity search covers only published entries by default", %{
      published: published,
      draft: draft
    } do
      assert {:ok, results} = Faq.find_most_similar_faqs(@embedding, 10)
      assert Enum.map(results, & &1.id) == [published.id]

      assert {:ok, results} = Faq.find_most_similar_faqs(@embedding, 10, statuses: [:draft])
      assert Enum.map(results, & &1.id) == [draft.id]
    end

    test "the answer context never contains drafts", %{published: published} do
      with_embeddings(fn ->
        assert {:ok, %{hits: hits}} =
                 Sanbase.Knowledge.retrieve_context("Published?",
                   query_understanding: false,
                   insight: false,
                   academy: false
                 )

        assert Enum.map(hits.faq, & &1.id) == [published.id]
      end)
    end

    test "export skips drafts", %{published: published} do
      path = Path.join(System.tmp_dir!(), "faq_drafts_#{System.unique_integer([:positive])}.json")
      on_exit(fn -> File.rm(path) end)

      assert {:ok, %{count: 1}} = FaqSync.export_to_file(path)
      assert [%{"id" => id}] = path |> File.read!() |> Jason.decode!() |> Map.fetch!("faqs")
      assert id == published.id
    end
  end
end
