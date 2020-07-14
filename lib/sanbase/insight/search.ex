defmodule Sanbase.Insight.Search do
  import Ecto.Query

  @doc ~s"""
  Provided a query which has `document_tokens` tsvector field and a search term,
  filter the results of the query that match the searching conditions only.
  """
  def run(query, search_term) do
    where(
      query,
      fragment(
        """
        document_tokens @@ plainto_tsquery(?)
        """,
        ^search_term
      )
    )
    |> Sanbase.Repo.all()
  end

  def update_document_tokens(post_id) do
    {:ok, %{num_rows: 1}} =
      Sanbase.Repo.query(
        """
        UPDATE posts
        SET document_tokens = (
          SELECT
            to_tsvector(
              posts.title || ' ' ||
              posts.text ||' ' ||
              coalesce((string_agg(tags.name, ' ')), '') || ' ' ||
              coalesce((string_agg(metrics.name, ' ')), '')
            )
          FROM posts
          LEFT OUTER JOIN posts_tags ON posts.id = posts_tags.post_id
          LEFT OUTER JOIN tags ON tags.id = posts_tags.tag_id
          LEFT OUTER JOIN posts_metrics ON posts.id = posts_metrics.post_id
          LEFT OUTER JOIN metrics ON metrics.id = posts_metrics.metric_id
          WHERE posts.id = $1::bigint
          GROUP BY posts.id
        )
        WHERE posts.id = $1::bigint
        """,
        [post_id]
      )

    :ok
  end

  def update_all_document_tokens() do
    {:ok, _} =
      Sanbase.Repo.query("""
      WITH cte AS (
        SELECT
          posts.id AS post_id,
          to_tsvector(
            posts.title || ' ' ||
            posts.text || ' ' ||
            coalesce((string_agg(tags.name, ' ')), '') || ' ' ||
            coalesce((string_agg(metrics.name, ' ')), '')
          ) AS doc_tokens
        FROM posts
        JOIN posts_tags ON posts.id = posts_tags.post_id
        JOIN tags ON tags.id = posts_tags.tag_id
        JOIN posts_metrics ON posts.id = posts_metrics.post_id
        JOIN metrics ON metrics.id = posts_metrics.metric_id
        GROUP BY posts.id
      )
      UPDATE posts
      SET document_tokens = cte.doc_tokens
      FROM cte
      WHERE posts.id = cte.post_id
      """)

    :ok
  end
end
