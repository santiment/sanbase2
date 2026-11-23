defmodule Sanbase.MCP.Dev.TweetsByAuthorTool do
  @moduledoc """
  Every indexed post by one X (Twitter) account in a time window, oldest first. Not a
  sample: `stats.total_matching` is exact, and `stats.truncated: true` means there were
  more posts than `max_posts`. Narrow the window or raise `max_posts` to get them all.
  Internal Santiment social data from metrics-hub; cite it as "Santiment social data".

  Only accounts Santiment's scrapers track are indexed. When there are no posts, read
  `note` and `stats.account_indexed`: `false` means Santiment does not track the
  account, not that it was quiet.

  Each post has `ts`, `text`, `url`, `is_retweet`, the engagement counts (`likes`,
  `replies`, `retweets`, `quotes`) and the bullish/bearish model scores (`bull`, `bear`,
  0 to 1).

  Results can be large (roughly 100-150 tokens per post). Do not read them in your main
  context. Write the result to a file when you can, then work from the file: compute
  numbers with code, and hand the post texts to a cheaper model or subagent to pull out
  topics, narratives and calls. If you can only read the result directly, keep
  `max_posts` small or set `include_retweets` to false.
  """

  use Anubis.Server.Component, type: :tool

  require Logger

  alias Anubis.Server.Response
  alias Sanbase.MCP.ToolError
  alias Sanbase.SocialData.TweetsByAuthor

  @default_max_posts 200
  @max_posts_limit 10_000

  def name(), do: "tweets_by_author"

  @impl true
  def annotations() do
    %{
      "title" => "Tweets by Author",
      "readOnlyHint" => true,
      "destructiveHint" => false,
      "openWorldHint" => false
    }
  end

  schema do
    field(:screen_name, :string,
      description:
        "The X handle: 'santimentdata', '@santimentdata' or the profile URL. " <>
          "Pass this or `author_id`."
    )

    field(:author_id, :string, description: "The numeric X user id, instead of `screen_name`.")

    field(:from, :string,
      description: "Window start: ISO-8601 or date math like 'now-30d'. Defaults to 7 days ago."
    )

    field(:to, :string,
      description: "Window end: ISO-8601 or date math like 'now'. Defaults to now."
    )

    field(:include_retweets, :boolean,
      description: "false keeps only the account's own posts. Defaults to true."
    )

    field(:sources, {:list, :string},
      description:
        "Twitter indices, any of: #{Enum.join(TweetsByAuthor.sources(), ", ")}. " <>
          "Defaults to all of them ('twitter')."
    )

    field(:max_posts, :integer,
      description:
        "Max posts to return (default #{@default_max_posts}, at most #{@max_posts_limit})."
    )
  end

  @impl true
  def execute(params, frame) do
    account = [screen_name: params[:screen_name], author_id: params[:author_id]]

    Logger.info(
      "[MCP Dev] User #{frame.assigns.current_user.id} tweets_by_author: #{inspect(account)}"
    )

    opts = [
      from: params[:from],
      to: params[:to],
      sources: params[:sources],
      include_retweets: params[:include_retweets],
      max_posts: params |> Map.get(:max_posts) |> clamp_max_posts()
    ]

    case TweetsByAuthor.fetch(account, opts) do
      {:ok, result} ->
        {:reply, Response.json(Response.tool(), result), frame}

      {:error, {kind, message}} ->
        {:reply, Response.error(Response.tool(), ToolError.tag(kind, message)), frame}
    end
  end

  defp clamp_max_posts(n) when is_integer(n) and n > 0, do: min(n, @max_posts_limit)
  defp clamp_max_posts(_), do: @default_max_posts
end
