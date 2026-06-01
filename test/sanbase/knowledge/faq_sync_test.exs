defmodule Sanbase.Knowledge.FaqSyncTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Knowledge.{FaqEntry, FaqSync}
  alias Sanbase.Repo

  setup do
    path =
      Path.join(System.tmp_dir!(), "faq_sync_test_#{System.unique_integer([:positive])}.json")

    on_exit(fn -> File.rm(path) end)
    {:ok, path: path}
  end

  defp insert_faq(attrs) do
    %FaqEntry{}
    |> FaqEntry.changeset(attrs)
    |> Repo.insert!()
  end

  describe "export_to_file/1 + import_from_file/1 round-trip" do
    test "copies question/answer/source_url/tags, preserving id, skipping embedding", %{
      path: path
    } do
      original =
        insert_faq(%{
          "question" => "What is MVRV?",
          "answer_markdown" => "Market Value to Realized Value.",
          "source_url" => "https://academy.santiment.net/mvrv",
          "tags" => ["mvrv", "onchain"]
        })

      assert {:ok, %{count: 1}} = FaqSync.export_to_file(path)

      # Wipe local FAQs (join rows first, to satisfy the FK), then import.
      Repo.delete_all("faq_entries_tags")
      Repo.delete_all(FaqEntry)

      assert {:ok, %{total: 1, inserted: 1, updated: 0, failed: 0}} =
               FaqSync.import_from_file(path)

      imported = Repo.get(FaqEntry, original.id) |> Repo.preload(:tags)
      assert imported.question == "What is MVRV?"
      assert imported.answer_markdown == "Market Value to Realized Value."
      assert imported.source_url == "https://academy.santiment.net/mvrv"
      assert Enum.sort(Enum.map(imported.tags, & &1.name)) == ["mvrv", "onchain"]
      # embedding is intentionally not copied — re-embed locally afterwards
      assert imported.embedding == nil
    end

    test "re-importing the same file updates in place (idempotent)", %{path: path} do
      insert_faq(%{"question" => "Q1", "answer_markdown" => "A1"})
      {:ok, _} = FaqSync.export_to_file(path)

      assert {:ok, %{inserted: 0, updated: 1, total: 1}} = FaqSync.import_from_file(path)
      assert Repo.aggregate(FaqEntry, :count) == 1
    end
  end
end
