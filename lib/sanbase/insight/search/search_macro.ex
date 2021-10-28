defmodule Sanbase.Insight.Search.Macro do
  defmacro plainto_tsquery_highlight_fragment(field, search_term) do
    quote do
      fragment(
        "ts_headline(?, plainto_tsquery(?), 'StartSel=<__internal_highlight__>, StopSel=</__internal_highlight__>')",
        unquote(field),
        unquote(search_term)
      )
    end
  end

  defmacro to_tsquery_highlight_fragment(field, search_term) do
    quote do
      fragment(
        "ts_headline(?, to_tsquery(?), 'StartSel=<__internal_highlight__>, StopSel=</__internal_highlight__>')",
        unquote(field),
        unquote(search_term)
      )
    end
  end

  defmacro plainto_tsquery_search_insights_fragment(search_term, limit, offset) do
    quote do
      fragment(
        """
        SELECT
          posts.id AS id,
          ts_rank(posts.document_tokens, plainto_tsquery(?)) AS rank,
          coalesce((string_agg(tags.name, ' ' ORDER BY tags.name)), '') AS tags_str,
          coalesce((string_agg(metrics.name, ' ' ORDER BY metrics.name)), '') AS metrics_str
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
        unquote(search_term),
        unquote(search_term),
        unquote(limit),
        unquote(offset)
      )
    end
  end

  defmacro to_tsquery_search_insights_fragment(search_term, limit, offset) do
    quote do
      fragment(
        """
        SELECT
          posts.id AS id,
          ts_rank(posts.document_tokens, to_tsquery(?)) AS rank,
          coalesce((string_agg(tags.name, ' ' ORDER BY tags.name)), '') AS tags_str,
          coalesce((string_agg(metrics.name, ' ' ORDER BY metrics.name)), '') AS metrics_str
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
        unquote(search_term),
        unquote(search_term),
        unquote(limit),
        unquote(offset)
      )
    end
  end
end
