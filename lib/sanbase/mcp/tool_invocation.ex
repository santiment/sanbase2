defmodule Sanbase.MCP.ToolInvocation do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Utils.Config

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
    :auth_method
  ]

  def changeset(invocation, attrs) do
    invocation
    |> cast(attrs, @fields)
    |> validate_required([:tool_name, :is_successful, :duration_ms])
  end

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

  defp do_extract(_tool_name, _params), do: {[], []}

  defp base_query, do: from(i in __MODULE__)

  defp apply_filters(query, opts) do
    query
    |> maybe_filter_tool_name(Keyword.get(opts, :tool_name))
    |> maybe_filter_user(Keyword.get(opts, :email_search))
    |> maybe_filter_metric(Keyword.get(opts, :metric))
  end

  defp maybe_filter_tool_name(query, nil), do: query
  defp maybe_filter_tool_name(query, ""), do: query

  defp maybe_filter_tool_name(query, tool_name) do
    where(query, [i], i.tool_name == ^tool_name)
  end

  defp maybe_filter_user(query, nil), do: query
  defp maybe_filter_user(query, ""), do: query

  defp maybe_filter_user(query, search) do
    escaped =
      search
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    search_term = "%#{escaped}%"

    from(i in query,
      join: u in assoc(i, :user),
      where: ilike(u.email, ^search_term)
    )
  end

  defp maybe_filter_metric(query, nil), do: query
  defp maybe_filter_metric(query, ""), do: query

  defp maybe_filter_metric(query, metric) do
    where(query, [i], fragment("? @> ?", i.metrics, type(^[metric], {:array, :string})))
  end

  defp apply_pagination(query, opts) do
    page = opts |> Keyword.get(:page, 1) |> max(1)
    page_size = opts |> Keyword.get(:page_size, 50) |> max(1) |> min(100)
    offset = (page - 1) * page_size

    query
    |> limit(^page_size)
    |> offset(^offset)
  end
end
