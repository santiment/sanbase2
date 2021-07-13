defmodule Sanbase.Insight.Search do
  import Ecto.Query

  @doc ~s"""
  Provided a query which has `document_tokens` tsvector field and a search term,
  filter the results of the query that match the searching conditions only.
  """

  def run(query, search_term) do
    from(
      post in query,
      join:
        id_and_rank in fragment(
          """
          SELECT posts.id AS id,
          ts_rank(posts.document_tokens, plainto_tsquery(?)) AS rank
          FROM posts
          WHERE posts.document_tokens @@ plainto_tsquery(?) OR posts.title ILIKE ?
          """,
          ^search_term,
          ^search_term,
          ^"%#{search_term}%"
        ),
      on: post.id == id_and_rank.id,
      order_by: [desc: id_and_rank.rank]
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
          ( setweight(to_tsvector('english', posts.title), 'A') ||
            setweight(to_tsvector('english', posts.text), 'C') ||
            setweight(to_tsvector('english', coalesce((string_agg(tags.name, ' ')), '')), 'B') ||
            setweight(to_tsvector('english', coalesce((string_agg(metrics.name, ' ')), '')), 'B')
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
            ( setweight(to_tsvector('english', posts.title), 'A') ||
              setweight(to_tsvector('english', posts.text), 'C') ||
              setweight(to_tsvector('english', coalesce((string_agg(tags.name, ' ')), '')), 'B') ||
              setweight(to_tsvector('english', coalesce((string_agg(metrics.name, ' ')), '')), 'B')
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
