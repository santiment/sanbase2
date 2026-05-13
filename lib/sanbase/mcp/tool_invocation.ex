defmodule Sanbase.MCP.ToolInvocation do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Utils.Config

  @user_agent_max 512
  @client_max 32
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
    |> update_change(:client, &truncate_client/1)
    |> validate_required([:tool_name, :is_successful, :duration_ms, :kind])
    |> validate_inclusion(:kind, @kinds)
  end

  @doc """
  Maps a raw User-Agent header to a client identifier. Matches the well-known
  clients (claude/chatgpt/cursor) and falls back to the raw UA string
  (truncated to the column's size limit) when no match is found. Returns nil
  only for nil input so legacy rows stay nil.
  """
  @spec derive_client_from_user_agent(String.t() | nil) :: String.t() | nil
  def derive_client_from_user_agent(nil), do: nil

  def derive_client_from_user_agent(ua) when is_binary(ua) do
    match_known_client(ua) || truncate_client(ua)
  end

  @doc """
  Derives the client identifier from the User-Agent header and the MCP
  `clientInfo` (from the `initialize` handshake). Many MCP clients (custom
  CLIs, some SDK wrappers) omit User-Agent but always provide clientInfo,
  so we try the header first, then clientInfo.name, and fall back to
  whichever raw string is present (truncated). Returns nil only when both
  inputs are absent.
  """
  @spec derive_client(String.t() | nil, map() | nil) :: String.t() | nil
  def derive_client(user_agent, client_info) do
    name = client_info_name(client_info)

    match_known_client(user_agent) ||
      match_known_client(name) ||
      truncate_client(name) ||
      truncate_client(user_agent)
  end

  @doc """
  Builds a synthetic User-Agent string from MCP `clientInfo` for invocations
  where the transport didn't carry a User-Agent header. Format: `name/version`
  (or just `name` if version is absent). Returns nil if clientInfo is empty.
  """
  @spec user_agent_from_client_info(map() | nil) :: String.t() | nil
  def user_agent_from_client_info(nil), do: nil

  def user_agent_from_client_info(%{} = ci) do
    case {client_info_name(ci), client_info_version(ci)} do
      {nil, _} -> nil
      {name, nil} -> name
      {name, version} -> "#{name}/#{version}"
    end
  end

  defp client_info_name(nil), do: nil
  defp client_info_name(%{} = ci), do: ci["name"] || ci[:name]
  defp client_info_version(%{} = ci), do: ci["version"] || ci[:version]

  defp match_known_client(nil), do: nil
  defp match_known_client(""), do: nil

  defp match_known_client(s) when is_binary(s) do
    cond do
      Regex.match?(~r/Claude/i, s) -> "claude"
      Regex.match?(~r/ChatGPT|OpenAI/i, s) -> "chatgpt"
      Regex.match?(~r/Cursor/i, s) -> "cursor"
      true -> nil
    end
  end

  defp match_known_client(_), do: nil

  defp truncate_user_agent(nil), do: nil
  defp truncate_user_agent(ua) when byte_size(ua) <= @user_agent_max, do: ua
  defp truncate_user_agent(ua), do: binary_part(ua, 0, @user_agent_max)

  defp truncate_client(nil), do: nil
  defp truncate_client(""), do: nil
  defp truncate_client(c) when byte_size(c) <= @client_max, do: c
  defp truncate_client(c), do: binary_part(c, 0, @client_max)

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
    base_query()
    |> where([i], i.inserted_at >= ^since_datetime)
    |> exclude_noise()
    |> group_by([i], i.tool_name)
    |> select([i], {i.tool_name, count(i.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Counts the invocation rows that the headline stats / timeline intentionally
  filter out (team-member traffic, rate-limit rejections, banned-attempt
  retries) in a given window. Returned as a map for a small "filtered out"
  side panel in the admin view.
  """
  @spec noise_counts_since(DateTime.t()) :: %{
          team: non_neg_integer(),
          rate_limited: non_neg_integer(),
          banned: non_neg_integer()
        }
  def noise_counts_since(since_datetime) do
    in_window = fn ->
      from(i in __MODULE__, where: i.inserted_at >= ^since_datetime)
    end

    rate_limited =
      in_window.()
      |> where([i], ilike(i.error_message, "Rate limit exceeded:%"))
      |> Repo.aggregate(:count, :id)

    banned =
      in_window.()
      |> where([i], i.error_message == "banned")
      |> Repo.aggregate(:count, :id)

    team =
      in_window.()
      |> join(:inner, [i], u in assoc(i, :user), as: :user)
      |> where(^team_member_condition())
      |> Repo.aggregate(:count, :id)

    %{team: team, rate_limited: rate_limited, banned: banned}
  end

  # Composes the OR'd email patterns ("@santiment.net" + each configured
  # team email) into a single dynamic clause. Requires a `[user: u]`
  # named binding on the query.
  defp team_member_condition do
    base = dynamic([user: u], ilike(u.email, "%@santiment.net"))

    Enum.reduce(team_emails(), base, fn email, dyn ->
      dynamic([user: u], ^dyn or ilike(u.email, ^email))
    end)
  end

  # LEFT JOIN users, exclude team members and rate-limit/banned-attempt rows.
  # Used by headline stats, timeline, and top_by — anywhere we want to count
  # "real" traffic without the auto-generated noise.
  defp exclude_noise(query) do
    query
    |> join(:left, [i], u in assoc(i, :user), as: :user)
    |> apply_team_exclusion(true)
    |> where(
      [i],
      is_nil(i.error_message) or
        (not ilike(i.error_message, "Rate limit exceeded:%") and i.error_message != "banned")
    )
  end

  def tool_names do
    from(i in __MODULE__,
      distinct: true,
      select: i.tool_name,
      order_by: i.tool_name
    )
    |> Repo.all()
  end

  @builtin_team_emails ["tsvetozar.penov@gmail.com"]

  @doc """
  List of additional team-member emails to exclude from admin views by
  default. Sourced from the `:team_emails` config (CSV string set from the
  `MCP_TEAM_EMAILS` env var), merged with a small built-in list of known
  personal accounts of teammates. Returned as a lower-cased, de-duplicated
  list; the `@santiment.net` domain is excluded unconditionally elsewhere
  and is not duplicated here.
  """
  @spec team_emails() :: [String.t()]
  def team_emails do
    configured =
      __MODULE__
      |> Config.module_get(:team_emails, "")
      |> to_string()
      |> String.split(",", trim: true)
      |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
      |> Enum.reject(&(&1 == ""))

    Enum.uniq(@builtin_team_emails ++ configured)
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
    |> exclude_noise()
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
    base_query()
    |> where([i], i.inserted_at >= ^since)
    |> exclude_noise()
    |> group_by([i], i.tool_name)
    |> order_by([i], desc: count(i.id))
    |> limit(^limit)
    |> select([i], {i.tool_name, count(i.id)})
    |> Repo.all()
  end

  def top_by(:client, %DateTime{} = since, limit) do
    base_query()
    |> where([i], i.inserted_at >= ^since)
    |> exclude_noise()
    |> group_by([i], i.client)
    |> order_by([i], desc: count(i.id))
    |> limit(^limit)
    |> select([i], {i.client, count(i.id)})
    |> Repo.all()
  end

  def top_by(:metric, %DateTime{} = since, limit) do
    base_query()
    |> where([i], i.inserted_at >= ^since)
    |> exclude_noise()
    |> join(:cross, [i], m in fragment("unnest(?)", i.metrics), as: :metric)
    |> group_by([metric: m], m)
    |> order_by([i], desc: count(i.id))
    |> limit(^limit)
    |> select([i, metric: m], {m, count(i.id)})
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
      group_by: [u.id, u.email, u.username, u.is_mcp_banned],
      having: count(i.id) >= ^min_hits,
      order_by: [desc: count(i.id)],
      limit: ^limit,
      select: %{
        user_id: u.id,
        email: u.email,
        username: u.username,
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
    # `||` fallbacks guard against Config.module_get returning nil when the
    # module env is registered (e.g. with :team_emails) but lacks these keys.
    limits = %{
      minute: Config.module_get(__MODULE__, :global_rate_limit_minute, 25) || 25,
      hour: Config.module_get(__MODULE__, :global_rate_limit_hour, 100) || 100,
      day: Config.module_get(__MODULE__, :global_rate_limit_day, 500) || 500
    }

    do_check_rate_limit(user_id, nil, limits)
  end

  @doc """
  Check per-tool rate limits. Only `combined_trends_tool` has specific limits.
  Other tools return {:ok, true} immediately.
  """
  def check_tool_rate_limit(user_id, "combined_trends_tool") do
    limits = %{
      minute: Config.module_get(__MODULE__, :combined_trends_rate_limit_minute, 3) || 3,
      hour: Config.module_get(__MODULE__, :combined_trends_rate_limit_hour, 20) || 20,
      day: Config.module_get(__MODULE__, :combined_trends_rate_limit_day, 50) || 50
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
    |> maybe_hide_auto_rejected(Keyword.get(opts, :hide_auto_rejected, false))
  end

  defp maybe_hide_auto_rejected(query, false), do: query

  defp maybe_hide_auto_rejected(query, true) do
    where(
      query,
      [i],
      is_nil(i.error_message) or
        (i.error_message != "banned" and not ilike(i.error_message, "Rate limit exceeded:%"))
    )
  end

  @doc """
  Number of distinct users with at least one rate-limit rejection in the
  given window. Used to badge the "Rate-limited users" tab so dashboards
  flash when new abusers appear.
  """
  @spec rate_limited_users_count(DateTime.t()) :: non_neg_integer()
  def rate_limited_users_count(%DateTime{} = since) do
    from(i in __MODULE__,
      where:
        i.inserted_at >= ^since and
          i.is_successful == false and
          ilike(i.error_message, "Rate limit exceeded:%") and
          not is_nil(i.user_id),
      select: count(i.user_id, :distinct)
    )
    |> Repo.one()
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
