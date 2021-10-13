defmodule Sanbase.Insight.Search do
  import Ecto.Query
  import Sanbase.Utils.Transform, only: [opts_to_limit_offset: 1]

  @doc ~s"""
  Provided a query which has `document_tokens` tsvector field and a search term,
  filter the results of the query that match the searching conditions only.
  """

  def run(query, search_term, opts) do
    case is_incomplete_word?(search_term) do
      true ->
        # Add `:*` to the end of the word so we can search for prefixes
        to_tsquery_incomplete_search(query, search_term, opts)

      false ->
        plainto_tsquery_complete_search(query, search_term, opts)
    end
  end

  defp is_incomplete_word?(search_term),
    do: String.match?(search_term, ~r/^[[:alnum:]]+$/)

  defp to_tsquery_incomplete_search(query, search_term, opts) do
    # The following heuristic is used here: If the search term is
    # a single alphanumeric word, we treat it as an incomplete word.
    # When the query is run on every keystroke we can show results
    # for every new character. For example if the search term is `mvrv`,
    # then we can show some results when only `mvr` is typed.
    # The function call appends `:*` to the search term and executes it
    # via the `to_tsquery` function instead of `plainto_tsquery` which
    # accepts a wider range of inputs and formats them.
    search_term = modify_search_term(search_term)
    {limit, offset} = opts_to_limit_offset(opts)

    from(
      post in query,
      join:
        map in fragment(
          """
          SELECT
            posts.id AS id,
            ts_rank(posts.document_tokens, to_tsquery(?)) AS rank,
            coalesce((string_agg(tags.name, ' ')), '') AS tags_str,
            coalesce((string_agg(metrics.name, ' ')), '') AS metrics_str
          FROM posts
          LEFT OUTER JOIN posts_tags ON posts.id = posts_tags.post_id
          LEFT OUTER JOIN tags ON tags.id = posts_tags.tag_id
          LEFT OUTER JOIN posts_metrics ON posts.id = posts_metrics.post_id
          LEFT OUTER JOIN metrics ON metrics.id = posts_metrics.metric_id
          WHERE posts.document_tokens @@ to_tsquery(?)
          GROUP BY posts.id
          ORDER BY rank DESC
          LIMIT ? OFFSET ?
          """,
          ^search_term,
          ^search_term,
          ^limit,
          ^offset
        ),
      on: post.id == map.id,
      select: %{
        post: post,
        rank: map.rank,
        highlights: %{
          title:
            fragment(
              "ts_headline(?, plainto_tsquery(?), 'StartSel=<__internal_highlight__>, StopSel=</__internal_highlight__>')",
              post.title,
              ^search_term
            ),
          text:
            fragment(
              "ts_headline(?, plainto_tsquery(?), 'StartSel=<__internal_highlight__>, StopSel=</__internal_highlight__>')",
              post.text,
              ^search_term
            ),
          tags:
            fragment(
              "ts_headline(?, plainto_tsquery(?), 'StartSel=<__internal_highlight__>, StopSel=</__internal_highlight__>')",
              map.tags_str,
              ^search_term
            ),
          metrics:
            fragment(
              "ts_headline(?, plainto_tsquery(?), 'StartSel=<__internal_highlight__>, StopSel=</__internal_highlight__>')",
              map.metrics_str,
              ^search_term
            )
        }
      },
      order_by: [desc: map.rank],
      limit: 10
    )
    |> Sanbase.Repo.all()
    |> transform_highlights()
  end

  defp plainto_tsquery_complete_search(query, search_term, opts) do
    {limit, offset} = opts_to_limit_offset(opts)

    from(
      post in query,
      join:
        map in fragment(
          """
          SELECT
            posts.id AS id,
            ts_rank(posts.document_tokens, plainto_tsquery(?)) AS rank,
            coalesce((string_agg(tags.name, ' ')), '') AS tags_str,
            coalesce((string_agg(metrics.name, ' ')), '') AS metrics_str
          FROM posts
          LEFT OUTER JOIN posts_tags ON posts.id = posts_tags.post_id
          LEFT OUTER JOIN tags ON tags.id = posts_tags.tag_id
          LEFT OUTER JOIN posts_metrics ON posts.id = posts_metrics.post_id
          LEFT OUTER JOIN metrics ON metrics.id = posts_metrics.metric_id
          WHERE posts.document_tokens @@ plainto_tsquery(?)
          GROUP BY posts.id
          ORDER BY rank DESC
          LIMIT ? OFFSET ?
          """,
          ^search_term,
          ^search_term,
          ^limit,
          ^offset
        ),
      on: post.id == map.id,
      select: %{
        post: post,
        rank: map.rank,
        highlights: %{
          title:
            fragment(
              "ts_headline(?, plainto_tsquery(?), 'StartSel=<__internal_highlight__>, StopSel=</__internal_highlight__>')",
              post.title,
              ^search_term
            ),
          text:
            fragment(
              "ts_headline(?, plainto_tsquery(?), 'StartSel=<__internal_highlight__>, StopSel=</__internal_highlight__>')",
              post.text,
              ^search_term
            ),
          tags:
            fragment(
              "ts_headline(?, plainto_tsquery(?), 'StartSel=<__internal_highlight__>, StopSel=</__internal_highlight__>')",
              map.tags_str,
              ^search_term
            ),
          metrics:
            fragment(
              "ts_headline(?, plainto_tsquery(?), 'StartSel=<__internal_highlight__>, StopSel=</__internal_highlight__>')",
              map.metrics_str,
              ^search_term
            )
        }
      },
      order_by: [desc: map.rank]
    )
    |> Sanbase.Repo.all()
    |> transform_highlights()
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

  # Extend the term so it is searching for prefixes
  defp modify_search_term(search_term) do
    case String.ends_with?(search_term, ":*") do
      true -> search_term
      false -> search_term <> ":*"
    end
  end

  defp transform_highlights(list) do
    list
    |> Enum.map(fn %{highlights: highlights} = map ->
      highlights = highlights |> Map.new(fn {k, v} -> {k, split_highlight_response(v)} end)
      Map.put(map, :highlights, highlights)
    end)
  end

  defp split_highlight_response(response) when is_binary(response) do
    starts_with_tag? = String.starts_with?(response, "<__internal_highlight__>")

    response
    |> String.split("<__internal_highlight__>", trim: true)
    |> Enum.flat_map(&String.split(&1, "</__internal_highlight__>", trim: true))
    |> Enum.reduce({[], starts_with_tag?}, fn text, {acc, highlight} ->
      acc = [%{highlight: highlight, text: text} | acc]
      {acc, !highlight}
    end)
    |> elem(0)
    |> Enum.reverse()
  end
end
