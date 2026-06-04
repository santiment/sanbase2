defmodule Sanbase.Knowledge.Academy do
  @moduledoc """
  Manage Academy articles indexed from the santiment/academy GitHub repository.

  Provides functionality for reentrant indexing, storing embeddings, and similarity search.
  """

  alias Sanbase.Knowledge.{AcademyArticle, AcademyArticleChunk}
  alias Sanbase.Repo

  import Ecto.Query

  require Logger

  @chunk_size 2000
  @chunk_overlap 200
  @embedding_size 1536
  @embedding_retry_attempts 3
  @embedding_retry_backoff_ms 2_000
  @github_repo_owner "santiment"
  @github_repo_name "academy"
  # Version of the indexing pipeline. The cache check in `maybe_use_cached/3`
  # treats an article as unchanged only when both `content_sha` AND
  # `index_version` match. Without this, source SHA matches alone would revive
  # stored chunks/embeddings even after the pipeline that produced them changed.
  #
  # Bump this constant whenever something that affects the derived data
  # changes, so cached articles get reindexed instead of silently serving
  # stale results. Examples:
  #   - chunk size / overlap (@chunk_size, @chunk_overlap)
  #   - embedding model or dimensions (@embedding_size)
  #   - chunking algorithm (TextChunker options, format)
  #   - heading / frontmatter / title extraction
  #   - any change to what gets stored on `AcademyArticleChunk`
  #
  # A bump invalidates every cached row and forces a full reindex on the next
  # run. The source SHA still short-circuits the GitHub content fetch for
  # articles whose markdown has not changed *and* whose pipeline version
  # matches the current one.
  #
  # v2: `to_academy_url/1` now strips the `ai-toolkit/` root section, fixing
  # academy_url for ai-toolkit articles that previously 404'd. Existing rows
  # have unchanged markdown, so without this bump the SHA-cache would keep the
  # stale URLs instead of re-deriving them.
  @index_version 2

  @excluded_paths MapSet.new([
                    "pull_request_template.md",
                    "src/docs/content/changelog/index.md"
                  ])

  @excluded_path_prefixes ["scripts/", "static/"]
  @excluded_basenames ["README.md", "GUIDE.md", "CONTRIBUTING.md", "CHANGELOG.md"]

  @type index_options :: [branch: String.t(), dry_run: boolean()]
  @type github_tree_entry :: %{
          path: String.t(),
          type: String.t(),
          sha: String.t()
        }

  @doc """
  Fetch all markdown articles from GitHub, chunk, embed, and store them.

  The function is reentrant: existing articles are marked stale, and stale entries are pruned
  after successful reindexing.
  """
  @spec reindex_academy(index_options()) :: :ok | {:error, term()}
  def reindex_academy(opts \\ []) do
    branch = Keyword.get(opts, :branch, "production")
    dry_run? = Keyword.get(opts, :dry_run, false)
    force? = Keyword.get(opts, :force, false)
    started_at = System.monotonic_time(:millisecond)

    log_tags =
      []
      |> then(&if(dry_run?, do: ["dry run" | &1], else: &1))
      |> then(&if(force?, do: ["force" | &1], else: &1))

    log_info("Starting Academy reindex for branch #{branch}", log_tags)

    result =
      if dry_run? do
        perform_dry_run(branch, force?)
      else
        do_reindex(branch, force?)
      end

    log_reindex_result(result, started_at, log_tags)
    result
  end

  @doc """
  Find the top `k` similar Academy chunks.

  Returns a list of maps containing the chunk content, similarity score, and metadata.
  """
  @spec search_chunks(String.t() | list(float()), pos_integer()) ::
          {:ok, list(map())} | {:error, term()}
  def search_chunks(query, top_k) when is_binary(query) and is_integer(top_k) and top_k > 0 do
    with {:ok, [embedding]} <- Sanbase.AI.Embedding.generate_embeddings([query], @embedding_size) do
      search_chunks(embedding, top_k)
    end
  end

  def search_chunks(embedding, top_k)
      when is_list(embedding) and is_integer(top_k) and top_k > 0 do
    chunks =
      from(chunk in AcademyArticleChunk,
        join: article in assoc(chunk, :article),
        where: chunk.is_stale == false and article.is_stale == false,
        order_by: [desc: fragment("1 - (embedding <=> ?)", ^embedding)],
        limit: ^top_k,
        select: %{
          similarity: fragment("1 - (embedding <=> ?)", ^embedding),
          chunk: chunk.content,
          title: article.title,
          url: article.academy_url,
          github_path: article.github_path,
          heading: chunk.heading,
          article_id: chunk.article_id,
          chunk_index: chunk.chunk_index
        }
      )
      |> Sanbase.Repo.VectorQuery.all()

    {:ok, chunks}
  end

  def search_chunks(_query, _k), do: {:error, :invalid_arguments}

  @doc """
  Find the top `k` similar Academy articles

  Returns a list of maps containing the academy article title, similarity score, and url
  """
  @spec search_articles(String.t() | list(float()), pos_integer()) ::
          {:ok, list(map())} | {:error, term()}
  def search_articles(query, top_k) when is_binary(query) and is_integer(top_k) and top_k > 0 do
    with {:ok, [embedding]} <- Sanbase.AI.Embedding.generate_embeddings([query], @embedding_size) do
      search_articles(embedding, top_k)
    end
  end

  def search_articles(embedding, top_k)
      when is_list(embedding) and is_integer(top_k) and top_k > 0 do
    articles =
      from(chunk in AcademyArticleChunk,
        join: article in assoc(chunk, :article),
        where: chunk.is_stale == false and article.is_stale == false,
        select: %{
          similarity: fragment("MAX(1 - (embedding <=> ?))", ^embedding),
          title: article.title,
          url: article.academy_url
        },
        group_by: [article.title, article.academy_url],
        order_by: [desc: fragment("MAX(1 - (embedding <=> ?))", ^embedding)],
        limit: ^top_k
      )
      |> Sanbase.Repo.VectorQuery.all()

    {:ok, articles}
  end

  # Helper functions for reindex_academy

  defp perform_dry_run(branch, force?) do
    with {:ok, tree_entries} <- fetch_repo_markdown_list(branch),
         {:ok, _result} <- process_markdown_entries(tree_entries, branch, true, force?) do
      :ok
    end
  end

  defp do_reindex(branch, force?) do
    with {:ok, tree_entries} <- fetch_repo_markdown_list(branch),
         {:ok, %{to_index: to_index, unchanged: unchanged}} <-
           process_markdown_entries(tree_entries, branch, false, force?) do
      Repo.transaction(fn ->
        mark_all_articles_stale()
        clear_stale_for_unchanged(unchanged)
        # Prune stale rows before upserting so their academy_url/github_path
        # do not block new inserts via the unique constraints.
        delete_stale_records()
        finalize_indexing(to_index)
      end)
      |> case do
        {:ok, :ok} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp log_reindex_result(result, started_at, log_tags) do
    duration_sec = calculate_duration_seconds(started_at)

    case result do
      :ok ->
        log_info("Finished Academy reindex in #{duration_sec}s", log_tags)

      {:error, reason} ->
        log_error("Academy reindex failed: #{inspect(reason)} in #{duration_sec}s", log_tags)
    end
  end

  defp calculate_duration_seconds(started_at) do
    duration_ms = System.monotonic_time(:millisecond) - started_at
    Float.round(duration_ms / 1000, 2)
  end

  defp mark_all_articles_stale do
    Repo.update_all(AcademyArticle, set: [is_stale: true])
    Repo.update_all(AcademyArticleChunk, set: [is_stale: true])
  end

  defp fetch_repo_markdown_list(branch) do
    owner = @github_repo_owner
    repo = @github_repo_name

    case github_api_request("/repos/#{owner}/#{repo}/git/trees/#{branch}?recursive=1") do
      {:ok, %{"tree" => entries}} when is_list(entries) ->
        markdown_entries =
          entries
          |> Enum.filter(fn %{"path" => path, "type" => type} ->
            type == "blob" and
              String.ends_with?(path, [".md", ".mdx"]) and
              not excluded_path?(path)
          end)
          |> Enum.map(&build_entry(&1, owner, repo, branch))

        case fetch_additional_sources(branch) do
          {:ok, extra_entries} -> {:ok, markdown_entries ++ extra_entries}
          {:error, reason} -> {:error, reason}
        end

      {:ok, body} ->
        {:error, {:unexpected_tree_response, body}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp process_markdown_entries(entries, branch, dry_run?, force?) do
    total = length(entries)
    init_acc = %{to_index: [], unchanged: []}

    result =
      entries
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, init_acc}, fn {entry, index}, {:ok, acc} ->
        case fetch_and_prepare_article(entry, branch, dry_run?, force?) do
          {:ok, article_attrs, chunks_attrs} ->
            log_progress(index + 1, total, entry.path)

            {:cont,
             {:ok,
              %{acc | to_index: [%{article: article_attrs, chunks: chunks_attrs} | acc.to_index]}}}

          {:unchanged, article_id} ->
            log_progress(
              index + 1,
              total,
              "#{entry.path} (unchanged, sha+index_version match)"
            )

            {:cont, {:ok, %{acc | unchanged: [article_id | acc.unchanged]}}}

          {:ignore, _reason} ->
            {:cont, {:ok, acc}}

          {:error, _reason} = error ->
            {:halt, error}
        end
      end)

    case result do
      {:ok, %{to_index: to_index, unchanged: unchanged}} ->
        {:ok, %{to_index: Enum.reverse(to_index), unchanged: unchanged}}

      error ->
        error
    end
  end

  defp fetch_and_prepare_article(entry, branch, dry_run?, force?) do
    path = entry.path
    repo_owner = Map.get(entry, :repo_owner, @github_repo_owner)
    repo_name = Map.get(entry, :repo_name, @github_repo_name)
    ref = Map.get(entry, :ref, branch)
    github_path = Map.get(entry, :github_path, path)
    incoming_sha = entry[:sha]

    case maybe_use_cached(github_path, incoming_sha, dry_run?, force?) do
      {:unchanged, article_id} ->
        {:unchanged, article_id}

      :no_cache ->
        do_fetch_and_prepare_article(entry, path, ref, repo_owner, repo_name, dry_run?)
    end
  end

  defp maybe_use_cached(_github_path, _sha, _dry_run?, true), do: :no_cache
  defp maybe_use_cached(_github_path, nil, _dry_run?, _force?), do: :no_cache
  defp maybe_use_cached(_github_path, _sha, true, _force?), do: :no_cache

  defp maybe_use_cached(github_path, incoming_sha, false, false) do
    case Repo.get_by(AcademyArticle, github_path: github_path) do
      %AcademyArticle{content_sha: ^incoming_sha, index_version: @index_version, id: id} ->
        {:unchanged, id}

      _ ->
        :no_cache
    end
  end

  defp do_fetch_and_prepare_article(entry, path, ref, repo_owner, repo_name, dry_run?) do
    case fetch_file_contents(path, ref, repo_owner, repo_name) do
      {:ok, %{content: markdown, sha: fetched_sha}} ->
        content_sha =
          entry[:sha] ||
            fetched_sha ||
            :crypto.hash(:sha256, markdown) |> Base.encode16(case: :lower)

        frontmatter = extract_frontmatter(markdown)

        academy_url =
          Map.get(entry, :academy_url) ||
            frontmatter_slug_url(frontmatter) ||
            to_academy_url(path)

        github_path = Map.get(entry, :github_path, path)
        # Only the sanpy additional source has predefined title at the moment.
        # All of the academy articles' titles will be extracted
        title =
          present_string(Map.get(entry, :title)) ||
            present_string(Map.get(frontmatter, :title)) ||
            extract_heading_title(markdown)

        article_attrs = %{
          github_path: github_path,
          academy_url: academy_url,
          title: title,
          content_sha: content_sha,
          is_stale: false
        }

        case build_chunks(markdown, dry_run?) do
          {:ok, chunks_attrs} ->
            {:ok, article_attrs, chunks_attrs}

          {:error, reason} ->
            {:error, {:chunk_build_failed, path, reason}}
        end

      {:error, :non_utf8} ->
        {:ignore, :non_utf8}

      {:error, error} ->
        {:error, {:fetch_file_failed, path, error}}
    end
  end

  defp fetch_file_contents(path, branch, repo_owner, repo_name) do
    encoded_path = URI.encode(path)

    case github_api_request(
           "/repos/#{repo_owner}/#{repo_name}/contents/#{encoded_path}?ref=#{branch}"
         ) do
      {:ok, %{"content" => content, "encoding" => "base64"} = body} ->
        case Base.decode64(content, ignore: :whitespace) do
          {:ok, data} ->
            if String.valid?(data) do
              {:ok, %{content: data, sha: Map.get(body, "sha")}}
            else
              {:error, :non_utf8}
            end

          :error ->
            {:error, :invalid_base64}
        end

      {:ok, _body} = unexpected ->
        {:error, {:unexpected_content_response, unexpected}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp build_chunks(markdown, dry_run?) do
    markdown
    |> chunk_markdown()
    |> maybe_embed_chunks(dry_run?)
  end

  defp chunk_markdown(markdown) do
    chunk_opts = [chunk_size: @chunk_size, chunk_overlap: @chunk_overlap, format: :markdown]

    chunks =
      markdown
      |> TextChunker.split(chunk_opts)
      |> Enum.with_index()
      |> Enum.map(fn {chunk, index} ->
        chunk_text = chunk.text |> String.trim()

        %{
          chunk_index: index,
          heading: extract_heading(chunk_text),
          content: chunk_text,
          is_stale: false
        }
      end)

    {:ok, chunks}
  end

  defp maybe_embed_chunks({:ok, chunks}, true) do
    {:ok, Enum.map(chunks, &Map.put(&1, :embedding, []))}
  end

  defp maybe_embed_chunks({:ok, chunks}, false) do
    embed_chunks_with_retry(chunks, @embedding_retry_attempts)
  end

  defp maybe_embed_chunks(error, _dry_run?), do: error

  defp embed_chunks_with_retry(_chunks, attempts) when attempts <= 0 do
    {:error, :too_many_embedding_failures}
  end

  defp embed_chunks_with_retry(chunks, attempts) do
    case embed_chunks(chunks) do
      {:ok, embedded_chunks} -> {:ok, embedded_chunks}
      {:error, reason} -> handle_embedding_failure(chunks, attempts, reason)
    end
  end

  defp embed_chunks(chunks) do
    payload = Enum.map(chunks, &format_chunk_for_embedding/1)

    case Sanbase.AI.Embedding.generate_embeddings(payload, @embedding_size) do
      {:ok, vectors} ->
        embedded_chunks =
          Enum.zip_with(chunks, vectors, fn chunk, embedding ->
            Map.put(chunk, :embedding, embedding)
          end)

        {:ok, embedded_chunks}

      {:error, reason} ->
        {:error, {:embedding_failed, reason}}
    end
  end

  defp handle_embedding_failure(chunks, attempts, {:embedding_failed, reason} = error) do
    remaining_attempts = attempts - 1

    if retryable_embedding_error?(reason) and remaining_attempts > 0 do
      backoff_ms = backoff_delay(attempts)

      log_error(
        "Embedding failed: #{inspect(reason)}. Retrying in #{backoff_ms}ms (#{remaining_attempts} attempts left)"
      )

      Process.sleep(backoff_ms)
      embed_chunks_with_retry(chunks, remaining_attempts)
    else
      {:error, error}
    end
  end

  defp handle_embedding_failure(_chunks, _attempts, error), do: {:error, error}

  defp retryable_embedding_error?(reason) when is_binary(reason) do
    downcased = String.downcase(reason)

    Enum.any?(
      ["timeout", "503", "unavailable", "reset", "connection"],
      &String.contains?(downcased, &1)
    )
  end

  defp retryable_embedding_error?(_reason), do: false

  defp backoff_delay(attempts) do
    multiplier = @embedding_retry_attempts - attempts + 1
    trunc(:math.pow(2, multiplier - 1) * @embedding_retry_backoff_ms)
  end

  defp finalize_indexing(articles) do
    Enum.each(articles, fn %{article: article_attrs, chunks: chunks_attrs} ->
      upsert_article_with_chunks(article_attrs, chunks_attrs)
    end)

    :ok
  end

  defp clear_stale_for_unchanged([]), do: :ok

  defp clear_stale_for_unchanged(article_ids) when is_list(article_ids) do
    Repo.update_all(
      from(a in AcademyArticle, where: a.id in ^article_ids),
      set: [is_stale: false]
    )

    Repo.update_all(
      from(c in AcademyArticleChunk, where: c.article_id in ^article_ids),
      set: [is_stale: false]
    )

    :ok
  end

  defp upsert_article_with_chunks(article_attrs, chunks_attrs) do
    article =
      AcademyArticle
      |> Repo.get_by(github_path: article_attrs.github_path)
      |> case do
        nil ->
          %AcademyArticle{}

        %AcademyArticle{} = article ->
          Repo.preload(article, :chunks)
      end

    {:ok, article} =
      article
      |> AcademyArticle.changeset(article_attrs)
      |> Ecto.Changeset.put_change(:index_version, @index_version)
      |> Repo.insert_or_update()

    Repo.delete_all(from(chunk in AcademyArticleChunk, where: chunk.article_id == ^article.id))

    insert_chunk_records(article.id, chunks_attrs)
  end

  defp insert_chunk_records(article_id, chunks_attrs) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      Enum.map(chunks_attrs, fn chunk ->
        chunk
        |> Map.put(:article_id, article_id)
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    Repo.insert_all(AcademyArticleChunk, entries)
  end

  defp delete_stale_records do
    Repo.delete_all(from(chunk in AcademyArticleChunk, where: chunk.is_stale))
    Repo.delete_all(from(article in AcademyArticle, where: article.is_stale))
  end

  defp format_chunk_for_embedding(%{content: content}), do: content

  defp extract_frontmatter(markdown) do
    markdown
    |> String.trim_leading()
    |> case do
      "---" <> rest ->
        with [frontmatter | _] <- String.split(rest, "---\n", parts: 2),
             {:ok, metadata} <- parse_frontmatter(frontmatter) do
          metadata
        else
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  defp frontmatter_slug_url(frontmatter) do
    case present_string(Map.get(frontmatter, :slug)) do
      nil ->
        nil

      slug ->
        case slug |> String.trim_leading("/") |> String.trim_trailing("/") do
          "" -> nil
          s -> "https://academy.santiment.net/#{s}/"
        end
    end
  end

  defp present_string(nil), do: nil

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp parse_frontmatter(text) do
    text
    |> String.split("\n")
    |> Enum.reduce_while(%{}, fn line, acc ->
      trimmed = String.trim(line)

      cond do
        trimmed == "" ->
          {:cont, acc}

        String.starts_with?(trimmed, "#") ->
          {:halt, {:error, :comments_not_supported}}

        true ->
          case String.split(trimmed, ":", parts: 2) do
            [key, value] ->
              key = String.trim(key)
              value = String.trim(value)
              value = value |> String.trim_leading("\"") |> String.trim_trailing("\"")
              # credo:disable-for-next-line
              {:cont, Map.put(acc, String.to_atom(key), value)}

            _ ->
              {:halt, {:error, :invalid_line}}
          end
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      metadata -> {:ok, metadata}
    end
  end

  defp extract_heading_title(markdown) do
    regex = ~r/^(#|##)\s+(?<title>.+)$/m

    case Regex.run(regex, markdown, capture: :all_but_first) do
      [title | _] -> String.trim(title)
      _ -> "Untitled Academy Article"
    end
  end

  defp extract_heading(chunk_text) do
    chunk_text
    |> String.split("\n")
    |> Enum.find(&String.starts_with?(&1, "#"))
    |> case do
      nil -> nil
      heading -> String.trim_leading(heading, "#") |> String.trim()
    end
  end

  # The academy site derives a doc's public URL by stripping the first path
  # segment when it is a "root section" (see `ROOT_SECTIONS` in the academy
  # repo's src/config/navigation.ts -> src/modules/navigation/paths.ts).
  # This list MUST stay in sync with that config; a missing entry produces URLs
  # with an extra leading segment that 404 (e.g. /ai-toolkit/mcp-connector/
  # instead of /mcp-connector/).
  defp to_academy_url(path) do
    path
    |> String.trim_leading("src/content/docs/")
    |> String.trim_leading("src/docs/")
    |> String.trim_leading("getting-started/")
    |> String.trim_leading("guides/")
    |> String.trim_leading("resources/")
    |> String.trim_leading("ai-toolkit/")
    |> String.trim_trailing("/index.mdx")
    |> String.trim_trailing("/index.md")
    |> String.replace_suffix(".md", "")
    |> String.replace_suffix(".mdx", "")
    |> String.replace("/index", "")
    |> case do
      "" -> "https://academy.santiment.net/"
      sanitized -> "https://academy.santiment.net/#{sanitized}/"
    end
  end

  defp github_api_request(path) do
    url = "https://api.github.com#{path}"

    headers =
      %{"Accept" => "application/vnd.github+json"}
      |> maybe_put_auth()

    req_opts = [headers: headers, receive_timeout: 60_000, connect_options: [timeout: 30_000]]

    case Req.get(url, req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp maybe_put_auth(headers) do
    case github_token() do
      nil -> headers
      token -> Map.put(headers, "Authorization", "Bearer #{token}")
    end
  end

  defp log_progress(current, total, path) do
    percent = Float.round(current / total * 100, 2)
    log_info("Indexed #{current}/#{total} (#{percent}%) - #{path}")
  end

  defp log_info(message, tags \\ []) do
    formatted_message = format_log_message(message, tags)
    Logger.info("[AcademyIndex] #{formatted_message}")
  end

  defp log_error(message, tags \\ []) do
    formatted_message = format_log_message(message, tags)
    Logger.error("[AcademyIndex] #{formatted_message}")
  end

  defp format_log_message(message, []), do: message

  defp format_log_message(message, tags) do
    tag_string = tags |> Enum.map(&"(#{&1})") |> Enum.join(" ")
    "#{tag_string} #{message}"
  end

  defp github_token do
    System.get_env("GITHUB_ACADEMY_SCRAPER_TOKEN")
  end

  defp build_entry(%{"path" => path, "sha" => sha}, owner, repo, branch) do
    %{
      path: path,
      sha: sha,
      repo_owner: owner,
      repo_name: repo,
      ref: branch,
      github_path: path,
      academy_url: nil
    }
  end

  defp fetch_additional_sources(branch) do
    additional_sources()
    |> Enum.reject(fn source ->
      excluded_path?(Map.get(source, :path), exclude_basenames?: false)
    end)
    |> Enum.map(fn source ->
      with {:ok, repo_owner} <- fetch_required(source, :repo_owner),
           {:ok, repo_name} <- fetch_required(source, :repo_name),
           {:ok, path} <- fetch_required(source, :path) do
        ref = Map.get(source, :ref, branch)

        case fetch_file_contents(path, ref, repo_owner, repo_name) do
          {:ok, %{sha: sha}} ->
            {:ok,
             %{
               path: path,
               sha: sha,
               repo_owner: repo_owner,
               repo_name: repo_name,
               ref: ref,
               github_path: Map.get(source, :github_path, path),
               academy_url: Map.get(source, :academy_url)
             }}

          {:error, reason} ->
            {:error, {:additional_source_fetch_failed, source, reason}}
        end
      else
        {:error, reason} -> {:error, {:invalid_additional_source, source, reason}}
      end
    end)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, entry}, {:ok, acc} -> {:cont, {:ok, [entry | acc]}}
      {:error, reason}, _ -> {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp fetch_required(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when value not in [nil, ""] -> {:ok, value}
      _ -> {:error, {:missing_required_key, key}}
    end
  end

  defp additional_sources do
    [
      %{
        repo_owner: "santiment",
        repo_name: "sanpy",
        title: "Sanpy - Santiment Python library for API access",
        ref: "master",
        path: "README.md",
        github_path: "sanpy/README.md",
        academy_url: "https://github.com/santiment/sanpy/blob/master/README.md"
      }
    ]
  end

  defp excluded_path?(path, opts \\ [])
  defp excluded_path?(nil, _opts), do: false

  defp excluded_path?(path, opts) do
    exclude_basenames? = Keyword.get(opts, :exclude_basenames?, true)

    MapSet.member?(@excluded_paths, path) or
      Enum.any?(@excluded_path_prefixes, &String.starts_with?(path, &1)) or
      (exclude_basenames? and Enum.member?(@excluded_basenames, Path.basename(path)))
  end
end
