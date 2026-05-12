defmodule Sanbase.MCP.ToolInvocation do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Utils.Config

  @user_agent_max 512
  @known_clients ~w(claude chatgpt cursor other)
  @kinds ~w(tool prompt)

  schema "mcp_tool_invocations" do
    belongs_to(:user, User)
    field(:tool_name, :string)
    field(:params, :map, default: %{})
    field(:metrics, {:array, :string}, default: [])
    field(:slugs, {:array, :string}, default: [])
    field(:response_size_bytes, :integer)
    field(:is_successful, :boolean)
    field(:error_message, :string)
    field(:duration_ms, :integer)
    field(:auth_method, :string)
    field(:user_agent, :string)
    field(:client, :string)
    field(:session_id, :string)
    field(:kind, :string, default: "tool")

    timestamps()
  end

  @fields [
    :user_id,
    :tool_name,
    :params,
    :metrics,
    :slugs,
    :response_size_bytes,
    :is_successful,
    :error_message,
    :duration_ms,
    :auth_method,
    :user_agent,
    :client,
    :session_id,
    :kind
  ]

  def changeset(invocation, attrs) do
    invocation
    |> cast(attrs, @fields)
    |> update_change(:user_agent, &truncate_user_agent/1)
    |> validate_required([:tool_name, :is_successful, :duration_ms, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:client, @known_clients)
  end

  @doc """
  Maps a raw User-Agent header to one of the known client identifiers.
  Returns nil for nil input so unknown legacy rows stay nil.
  """
  @spec derive_client_from_user_agent(String.t() | nil) :: String.t() | nil
  def derive_client_from_user_agent(nil), do: nil

  def derive_client_from_user_agent(ua) when is_binary(ua) do
    cond do
      Regex.match?(~r/Claude/i, ua) -> "claude"
      Regex.match?(~r/ChatGPT|OpenAI/i, ua) -> "chatgpt"
      Regex.match?(~r/Cursor/i, ua) -> "cursor"
      true -> "other"
    end
  end

  defp truncate_user_agent(nil), do: nil
  defp truncate_user_agent(ua) when byte_size(ua) <= @user_agent_max, do: ua
  defp truncate_user_agent(ua), do: binary_part(ua, 0, @user_agent_max)

  def create(attrs) do
    attrs = extract_metrics_and_slugs(attrs)

    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def list_invocations(opts \\ []) do
    base_query()
    |> apply_filters(opts)
    |> apply_pagination(opts)
    |> order_by([i], desc: i.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  def count_invocations(opts \\ []) do
    base_query()
    |> apply_filters(opts)
    |> Repo.aggregate(:count, :id)
  end

  def stats_since(since_datetime) do
    from(i in __MODULE__,
      where: i.inserted_at >= ^since_datetime,
      group_by: i.tool_name,
      select: {i.tool_name, count(i.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  def tool_names do
    from(i in __MODULE__,
      distinct: true,
      select: i.tool_name,
      order_by: i.tool_name
    )
    |> Repo.all()
  end

  @doc """
  List of additional team-member emails to exclude from admin views by
  default. Sourced from the `:team_emails` config (CSV string set from the
  `MCP_TEAM_EMAILS` env var). Returned as a lower-cased list; the
  `@santiment.net` domain is excluded unconditionally elsewhere and is not
  duplicated here.
  """
  @spec team_emails() :: [String.t()]
  def team_emails do
    __MODULE__
    |> Config.module_get(:team_emails, "")
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Bucketed usage time series. Returns rows of `{bucket_ts, total, unique_users}`
  ordered by bucket ascending.

  Options:
    * `:since` (DateTime, required) — lower bound on `inserted_at`.
    * `:bucket` (`"hour" | "day"`, default `"day"`) — date_trunc unit.
    * `:tool_name` (string) — filter by tool/prompt name.
    * `:client` (string) — filter by derived client.
    * `:kind` (`"tool" | "prompt"`) — filter by kind.
  """
  def time_series(opts) do
    since = Keyword.fetch!(opts, :since)
    bucket = Keyword.get(opts, :bucket, "day")

    base_query()
    |> where([i], i.inserted_at >= ^since)
    |> maybe_filter_tool_name(Keyword.get(opts, :tool_name))
    |> maybe_filter_client(Keyword.get(opts, :client))
    |> maybe_filter_kind(Keyword.get(opts, :kind))
    |> group_by([i], selected_as(:bucket))
    |> order_by([i], asc: selected_as(:bucket))
    |> select(
      [i],
      {selected_as(fragment("date_trunc(?, ?)", ^bucket, i.inserted_at), :bucket), count(i.id),
       fragment("COUNT(DISTINCT ?)", i.user_id)}
    )
    |> Repo.all()
  end

  @doc """
  Top groups by `:tool_name`, `:client`, or `:metric` for a time window.
  Returns `[{group_value, count}]` ordered desc; `limit` defaults to 10.
  """
  def top_by(dimension, since, limit \\ 10)

  def top_by(:tool_name, %DateTime{} = since, limit) do
    from(i in __MODULE__,
      where: i.inserted_at >= ^since,
      group_by: i.tool_name,
      order_by: [desc: count(i.id)],
      limit: ^limit,
      select: {i.tool_name, count(i.id)}
    )
    |> Repo.all()
  end

  def top_by(:client, %DateTime{} = since, limit) do
    from(i in __MODULE__,
      where: i.inserted_at >= ^since,
      group_by: i.client,
      order_by: [desc: count(i.id)],
      limit: ^limit,
      select: {i.client, count(i.id)}
    )
    |> Repo.all()
  end

  def top_by(:metric, %DateTime{} = since, limit) do
    from(i in __MODULE__,
      where: i.inserted_at >= ^since,
      cross_join: m in fragment("unnest(?)", i.metrics),
      group_by: m,
      order_by: [desc: count(i.id)],
      limit: ^limit,
      select: {m, count(i.id)}
    )
    |> Repo.all()
  end

  @doc """
  Lists users with rate-limit rejections in the given window.

  Options:
    * `:since` (DateTime, required) — lower bound on `inserted_at`.
    * `:min_hits` (integer, default 1) — minimum number of rate-limit rejections.
    * `:limit` (integer, default 100).

  Returns rows of `%{user_id, email, hits, last_hit, is_mcp_banned}` ordered
  by `hits` desc.
  """
  def rate_limited_users(opts) do
    since = Keyword.fetch!(opts, :since)
    min_hits = Keyword.get(opts, :min_hits, 1)
    limit = Keyword.get(opts, :limit, 100)

    from(i in __MODULE__,
      join: u in assoc(i, :user),
      where:
        i.inserted_at >= ^since and
          i.is_successful == false and
          ilike(i.error_message, "Rate limit exceeded:%"),
      group_by: [u.id, u.email, u.is_mcp_banned],
      having: count(i.id) >= ^min_hits,
      order_by: [desc: count(i.id)],
      limit: ^limit,
      select: %{
        user_id: u.id,
        email: u.email,
        hits: count(i.id),
        last_hit: max(i.inserted_at),
        is_mcp_banned: u.is_mcp_banned
      }
    )
    |> Repo.all()
  end

  @doc """
  Check global rate limits for a user across all MCP tool invocations.
  Returns {:ok, true} if under limits, {:error, message} if rate limited.
  """
  def check_rate_limit(user_id) do
    limits = %{
      minute: Config.module_get(__MODULE__, :global_rate_limit_minute, 25),
      hour: Config.module_get(__MODULE__, :global_rate_limit_hour, 100),
      day: Config.module_get(__MODULE__, :global_rate_limit_day, 500)
    }

    do_check_rate_limit(user_id, nil, limits)
  end

  @doc """
  Check per-tool rate limits. Only `combined_trends_tool` has specific limits.
  Other tools return {:ok, true} immediately.
  """
  def check_tool_rate_limit(user_id, "combined_trends_tool") do
    limits = %{
      minute: Config.module_get(__MODULE__, :combined_trends_rate_limit_minute, 3),
      hour: Config.module_get(__MODULE__, :combined_trends_rate_limit_hour, 20),
      day: Config.module_get(__MODULE__, :combined_trends_rate_limit_day, 50)
    }

    do_check_rate_limit(user_id, "combined_trends_tool", limits)
  end

  def check_tool_rate_limit(_user_id, _tool_name), do: {:ok, true}

  defp do_check_rate_limit(user_id, tool_name, limits) do
    entity_name = if tool_name, do: "#{tool_name} calls", else: "MCP tool calls"
    now = NaiveDateTime.utc_now()

    query =
      from(i in __MODULE__,
        where: i.user_id == ^user_id,
        select: %{
          day:
            fragment(
              "COUNT(*) FILTER (WHERE inserted_at >= ?)",
              ^NaiveDateTime.add(now, -86_400, :second)
            ),
          hour:
            fragment(
              "COUNT(*) FILTER (WHERE inserted_at >= ?)",
              ^NaiveDateTime.add(now, -3600, :second)
            ),
          minute:
            fragment(
              "COUNT(*) FILTER (WHERE inserted_at >= ?)",
              ^NaiveDateTime.add(now, -60, :second)
            )
        }
      )

    query =
      if tool_name do
        where(query, [i], i.tool_name == ^tool_name)
      else
        query
      end

    counts = Repo.one(query)

    cond do
      counts.minute >= limits.minute ->
        {:error,
         "Rate limit exceeded: #{counts.minute}/#{limits.minute} #{entity_name} per minute. " <>
           "Please wait up to 60 seconds before trying again."}

      counts.hour >= limits.hour ->
        {:error,
         "Rate limit exceeded: #{counts.hour}/#{limits.hour} #{entity_name} per hour. " <>
           "Please wait before trying again."}

      counts.day >= limits.day ->
        {:error,
         "Rate limit exceeded: #{counts.day}/#{limits.day} #{entity_name} per day. " <>
           "Daily limit resets after 24 hours from your earliest call."}

      true ->
        {:ok, true}
    end
  end

  defp extract_metrics_and_slugs(attrs) do
    params = Map.get(attrs, :params) || Map.get(attrs, "params") || %{}
    tool_name = Map.get(attrs, :tool_name) || Map.get(attrs, "tool_name") || ""

    {metrics, slugs} = do_extract(tool_name, params)

    attrs
    |> Map.put(:metrics, metrics)
    |> Map.put(:slugs, slugs)
  end

  defp do_extract("fetch_metric_data_tool", params) do
    metrics = List.wrap(params["metric"])
    slugs = List.wrap(params["slugs"] || params["slug"])
    {metrics, slugs}
  end

  defp do_extract("assets_by_metric_tool", params) do
    metrics = List.wrap(params["metric"])
    {metrics, []}
  end

  defp do_extract("metrics_and_assets_discovery_tool", params) do
    metric = params["metric"]
    metrics = if metric, do: List.wrap(metric), else: []
    {metrics, []}
  end

  defp do_extract("market_analysis_prompt", params) do
    slug = params["slug"] || params["asset"]
    {[], if(slug, do: [slug], else: [])}
  end

  defp do_extract("market_thesis_validation_prompt", params) do
    slug = params["slug"] || params["asset"]
    {[], if(slug, do: [slug], else: [])}
  end

  defp do_extract(_tool_name, _params), do: {[], []}

  defp base_query, do: from(i in __MODULE__)

  defp apply_filters(query, opts) do
    email_search = opts |> Keyword.get(:email_search) |> normalize_search()
    exclude_team = Keyword.get(opts, :exclude_team_members, false)

    query
    |> maybe_filter_tool_name(Keyword.get(opts, :tool_name))
    |> apply_user_filters(email_search, exclude_team)
    |> maybe_filter_metric(Keyword.get(opts, :metric))
  end

  defp normalize_search(nil), do: ""
  defp normalize_search(s) when is_binary(s), do: String.trim(s)

  defp maybe_filter_tool_name(query, nil), do: query
  defp maybe_filter_tool_name(query, ""), do: query

  defp maybe_filter_tool_name(query, tool_name) do
    where(query, [i], i.tool_name == ^tool_name)
  end

  defp apply_user_filters(query, "", false), do: query

  defp apply_user_filters(query, email_search, exclude_team) do
    # Email search needs the user row, so an INNER join (which also drops
    # anonymous invocations — matching the previous behavior). Team-member
    # exclusion alone uses a LEFT join so anonymous calls are not dropped.
    query =
      if email_search != "" do
        from(i in query, join: u in assoc(i, :user), as: :user)
      else
        from(i in query, left_join: u in assoc(i, :user), as: :user)
      end

    query
    |> apply_email_search(email_search)
    |> apply_team_exclusion(exclude_team)
  end

  defp apply_email_search(query, ""), do: query

  defp apply_email_search(query, search) do
    escaped =
      search
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    term = "%#{escaped}%"
    where(query, [user: u], ilike(u.email, ^term))
  end

  defp apply_team_exclusion(query, false), do: query

  defp apply_team_exclusion(query, true) do
    query =
      where(
        query,
        [user: u],
        is_nil(u.email) or not ilike(u.email, "%@santiment.net")
      )

    Enum.reduce(team_emails(), query, fn email, q ->
      where(q, [user: u], is_nil(u.email) or not ilike(u.email, ^email))
    end)
  end

  defp maybe_filter_metric(query, nil), do: query
  defp maybe_filter_metric(query, ""), do: query

  defp maybe_filter_metric(query, metric) do
    where(query, [i], fragment("? @> ?", i.metrics, type(^[metric], {:array, :string})))
  end

  defp maybe_filter_client(query, nil), do: query
  defp maybe_filter_client(query, ""), do: query
  defp maybe_filter_client(query, client), do: where(query, [i], i.client == ^client)

  defp maybe_filter_kind(query, nil), do: query
  defp maybe_filter_kind(query, ""), do: query
  defp maybe_filter_kind(query, kind), do: where(query, [i], i.kind == ^kind)

  defp apply_pagination(query, opts) do
    page = opts |> Keyword.get(:page, 1) |> max(1)
    page_size = opts |> Keyword.get(:page_size, 50) |> max(1) |> min(100)
    offset = (page - 1) * page_size

    query
    |> limit(^page_size)
    |> offset(^offset)
  end
end
