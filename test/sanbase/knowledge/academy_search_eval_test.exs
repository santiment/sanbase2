defmodule Sanbase.Knowledge.AcademySearchEvalTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Knowledge.{AcademyArticle, AcademyArticleChunk, AcademySearchEval}
  alias Sanbase.Repo

  @embedding_size 1536

  setup do
    mvrv = insert_article("MVRV", "https://academy.santiment.net/metrics/mvrv/")
    nvt = insert_article("NVT", "https://academy.santiment.net/metrics/nvt/")

    insert_chunk(mvrv, 0, "Usage Guide", "## Usage Guide\n\nMVRV of 2 means holders double.", 0)
    insert_chunk(nvt, 0, nil, "---\ntitle: NVT\n---\nshort", 1)

    path = Path.join(System.tmp_dir!(), "academy_eval_#{System.unique_integer([:positive])}.exs")

    File.write!(path, """
    %{
      items: [
        %{id: "a", question: "what is mvrv", type: "definition", negative: false,
          expected_urls: ["https://academy.santiment.net/metrics/mvrv/"], acceptable_urls: [],
          answer_facts: ["mvrv of 2 means holders double", "not in the docs"]},
        %{id: "n", question: "google trends", type: "not_in_academy", negative: true,
          expected_urls: [], acceptable_urls: [], answer_facts: []}
      ]
    }
    """)

    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  test "scores the production search path at page level", %{path: path} do
    result =
      Sanbase.Mock.prepare_mock2(
        &Sanbase.AI.Embedding.generate_embeddings/2,
        {:ok, [unit_vector(0)]}
      )
      |> Sanbase.Mock.run_with_mocks(fn -> AcademySearchEval.run(file: path, runs: 2) end)

    %{summary: summary, items: [answerable, negative]} = result

    assert answerable.primary_rank == 1
    assert answerable.hit_at_1
    assert answerable.fact_recall == 0.5
    assert answerable.stability == 1.0
    assert answerable.markup_top5 == 1
    assert length(answerable.latency_ms) == 2

    assert negative.negative
    assert is_float(negative.max_similarity)

    assert summary.answerable == 1
    assert summary.hit_at_1 == 1.0
    assert summary.mrr == 1.0
    assert summary.relevant_at_1 == 1.0
    assert summary.errors == 0

    # The result round-trips through JSON for later comparison.
    json_path = path <> ".json"
    AcademySearchEval.save(result, json_path)
    on_exit(fn -> File.rm(json_path) end)
    assert %{summary: %{hit_at_1: 1.0}} = AcademySearchEval.load(json_path)
  end

  test "index_stats/0 reports noise in the stored chunks" do
    stats = AcademySearchEval.index_stats()

    assert stats.articles == 2
    assert stats.chunks == 2
    assert stats.markup_chunks == 1
    assert stats.stub_chunks == 2
    assert stats.nil_heading_chunks == 1
  end

  defp insert_article(title, url) do
    %AcademyArticle{}
    |> AcademyArticle.changeset(%{
      title: title,
      academy_url: url,
      github_path: "src/#{title}.md",
      content_sha: "sha",
      is_stale: false
    })
    |> Repo.insert!()
  end

  defp insert_chunk(article, index, heading, content, axis) do
    %AcademyArticleChunk{}
    |> AcademyArticleChunk.changeset(%{
      article_id: article.id,
      chunk_index: index,
      heading: heading,
      content: content,
      embedding: unit_vector(axis),
      is_stale: false
    })
    |> Repo.insert!()
  end

  defp unit_vector(index), do: List.duplicate(0.0, @embedding_size) |> List.replace_at(index, 1.0)
end
