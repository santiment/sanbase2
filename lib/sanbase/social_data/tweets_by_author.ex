defmodule Sanbase.SocialData.TweetsByAuthor do
  @moduledoc """
  Every indexed post by one X (Twitter) account in a time window, from metrics-hub's
  `/tweets_by_author`: oldest first, with an exact `total_matching` and a `truncated` flag.
  Not a sample.

  Only accounts Santiment's scrapers track are indexed. For an empty window metrics-hub
  reports whether the account has any indexed post at all (`account_indexed`) and when
  the latest one was (`latest_indexed_post`).
  """

  alias Sanbase.SocialData.MetricsHubClient

  @sources ~w(twitter twitter_crypto twitter_news twitter_nft)
  @screen_name_regex ~r/^[A-Za-z0-9_]{1,15}$/
  @author_id_regex ~r/^[0-9]{1,20}$/
  @x_url_regex ~r{^(?:https?://)?(?:www\.|mobile\.)?(?:x|twitter)\.com(?:[/?#]|$)}i
  # First path segments of x.com pages that are not profiles.
  @reserved_paths ~w(i intent home search hashtag explore notifications messages settings
                     share compose login signup tos privacy)

  @type account :: [screen_name: String.t() | nil, author_id: String.t() | integer() | nil]
  @type opts :: [
          from: String.t() | nil,
          to: String.t() | nil,
          sources: [String.t()] | nil,
          include_retweets: boolean() | nil,
          max_posts: pos_integer() | nil
        ]
  @type error :: {:permanent | :transient | :unknown, String.t()}

  @doc "The source ids metrics-hub accepts. `twitter` means all the twitter indices."
  @spec sources() :: [String.t()]
  def sources(), do: @sources

  @doc """
  Fetch the posts of the account given by `:screen_name` (a handle, `@handle` or profile
  URL) or `:author_id` (the numeric X user id).

  Options:
    * `:from`, `:to` - ISO-8601 or Elasticsearch date math (`now-30d`). metrics-hub
      defaults to the last 7 days.
    * `:sources` - source ids from `sources/0`. Defaults to all twitter indices.
    * `:include_retweets` - `false` keeps only the account's own posts. Defaults to `true`.
    * `:max_posts` - the most posts to return. metrics-hub caps it at 10,000.
  """
  @spec fetch(account(), opts()) :: {:ok, map()} | {:error, error()}
  def fetch(account, opts \\ []) do
    with {:ok, account_body} <- account_body(account),
         {:ok, sources} <- validate_sources(opts[:sources]) do
      body =
        %{
          from_timestamp: normalize_time(opts[:from]),
          to_timestamp: normalize_time(opts[:to]),
          sources: sources && Enum.join(sources, ","),
          include_retweets: opts[:include_retweets],
          max_posts: opts[:max_posts]
        }
        |> Map.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.merge(account_body)

      case MetricsHubClient.post("/tweets_by_author", body) do
        {:ok, %{"stats" => stats, "posts" => posts} = data}
        when is_map(stats) and is_list(posts) ->
          {:ok, maybe_add_note(data)}

        {:ok, data} ->
          MetricsHubClient.unexpected(data)

        {:error, _} = error ->
          error
      end
    end
  end

  @doc """
  Parse a handle, `@handle` or x.com/twitter.com link into `%{screen_name: _}` or
  `%{author_id: _}`. Links that name no account are rejected.
  """
  @spec parse_screen_name(String.t()) ::
          {:ok, %{screen_name: String.t()} | %{author_id: String.t()}} | {:error, error()}
  def parse_screen_name(screen_name) when is_binary(screen_name) do
    trimmed = String.trim(screen_name)

    if Regex.match?(@x_url_regex, trimmed) do
      parse_x_url(trimmed, screen_name)
    else
      validate_handle(String.trim_leading(trimmed, "@"), screen_name)
    end
  end

  defp parse_x_url(url, input) do
    uri = URI.parse(if url =~ ~r{^https?://}i, do: url, else: "https://" <> url)
    segments = String.split(uri.path || "", "/", trim: true)
    query = URI.decode_query(uri.query || "")

    cond do
      match?(["i", "user", _ | _], segments) ->
        segments |> Enum.at(2) |> validate_author_id(input)

      Map.has_key?(query, "user_id") ->
        validate_author_id(query["user_id"], input)

      Map.has_key?(query, "screen_name") ->
        validate_handle(String.trim_leading(query["screen_name"], "@"), input)

      segments == [] or String.downcase(hd(segments)) in @reserved_paths ->
        {:error,
         {:permanent,
          "#{inspect(input)} is not a link to an X account. Pass the account's handle, its " <>
            "profile URL (x.com/<handle>) or its numeric `author_id`."}}

      true ->
        validate_handle(hd(segments), input)
    end
  end

  defp validate_handle(name, input) do
    if Regex.match?(@screen_name_regex, name) do
      {:ok, %{screen_name: name}}
    else
      {:error,
       {:permanent,
        "Invalid X screen name #{inspect(input)}: expected 1-15 letters, digits or " <>
          "underscores, optionally as @handle or a profile URL."}}
    end
  end

  defp validate_author_id(id, input) do
    if Regex.match?(@author_id_regex, id),
      do: {:ok, %{author_id: id}},
      else: {:error, {:permanent, "#{inspect(input)} has no valid numeric X user id."}}
  end

  defp account_body(account) do
    author_id = account[:author_id] |> to_string() |> String.trim()
    screen_name = account[:screen_name] |> to_string() |> String.trim()

    cond do
      author_id != "" ->
        if Regex.match?(@author_id_regex, author_id),
          do: {:ok, %{author_id: author_id}},
          else: {:error, {:permanent, "`author_id` must be a numeric X user id."}}

      screen_name != "" ->
        parse_screen_name(screen_name)

      true ->
        {:error, {:permanent, "Pass `screen_name` or `author_id`."}}
    end
  end

  defp validate_sources(nil), do: {:ok, nil}
  defp validate_sources([]), do: {:ok, nil}

  defp validate_sources(sources) when is_list(sources) do
    sources = sources |> Enum.map(&normalize_source/1) |> Enum.uniq()

    case Enum.reject(sources, &(&1 in @sources)) do
      [] ->
        {:ok, sources}

      unknown ->
        {:error,
         {:permanent,
          "Unknown source(s) #{Enum.join(unknown, ", ")}. Valid sources: " <>
            Enum.join(@sources, ", ")}}
    end
  end

  defp normalize_source(source) when is_binary(source),
    do: source |> String.trim() |> String.downcase()

  defp normalize_source(source), do: inspect(source)

  # Santiment-style date math (`utc_now-24h`) is `now-24h` in Elasticsearch.
  defp normalize_time(nil), do: nil

  defp normalize_time(time) when is_binary(time) do
    case String.trim(time) do
      "" -> nil
      time -> String.replace(time, "utc_now", "now")
    end
  end

  defp maybe_add_note(%{"posts" => [], "stats" => stats} = data) do
    note =
      case stats do
        %{"account_indexed" => false} ->
          "Santiment does not index this account: no post by it was ever collected. " <>
            "This says nothing about whether the account posted."

        %{"account_indexed" => true, "latest_indexed_post" => latest} ->
          "The account is indexed but posted nothing in this window. Its latest indexed " <>
            "post is from #{latest}."

        _ ->
          "No posts by this account in this window."
      end

    Map.put(data, "note", note)
  end

  defp maybe_add_note(data), do: data
end
