defmodule Sanbase.Knowledge.AcademyIndexBackupTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Knowledge.{Academy, AcademyArticle, AcademyArticleChunk}
  alias Sanbase.Repo

  @embedding_size 1536

  test "restore_index/1 brings back the index saved by backup_index/1" do
    article = insert_article("src/content/docs/resources/metrics/mvrv/index.mdx")
    insert_chunk(article, "MVRV compares market value to realized value.")

    # DDL is transactional in Postgres, so the backup tables vanish with the sandbox.
    assert :ok = Academy.backup_index("test_restore")

    # Simulate a reindex that replaced everything.
    Repo.delete_all(AcademyArticleChunk)
    Repo.delete_all(AcademyArticle)
    other = insert_article("src/content/docs/guides/other/index.mdx")
    insert_chunk(other, "Something else.")

    assert :ok = Academy.restore_index("test_restore")

    assert [%AcademyArticle{github_path: "src/content/docs/resources/metrics/mvrv/index.mdx"}] =
             Repo.all(AcademyArticle)

    assert [%AcademyArticleChunk{content: "MVRV compares market value to realized value."}] =
             Repo.all(AcademyArticleChunk)
  end

  test "rejects backup suffixes that are not plain identifiers" do
    assert {:error, :invalid_backup_suffix} = Academy.backup_index("x; DROP TABLE users")
    assert {:error, :invalid_backup_suffix} = Academy.restore_index("")
  end

  defp insert_article(github_path) do
    %AcademyArticle{}
    |> AcademyArticle.changeset(%{
      title: "Article",
      academy_url: "https://academy.santiment.net/#{System.unique_integer([:positive])}/",
      github_path: github_path,
      content_sha: "sha",
      is_stale: false
    })
    |> Repo.insert!()
  end

  defp insert_chunk(article, content) do
    %AcademyArticleChunk{}
    |> AcademyArticleChunk.changeset(%{
      article_id: article.id,
      chunk_index: 0,
      content: content,
      embedding: List.duplicate(0.0, @embedding_size) |> List.replace_at(0, 1.0),
      is_stale: false
    })
    |> Repo.insert!()
  end
end
