defmodule Sanbase.ExternalServices.Coinmarketcap.ScheduleRescrapePrice do
  @moduledoc ~s"""
  A rescrape of the coinmarketcap prices of a project in the [from, to) interval.

  A rescrape has its own cursor (`progress_datetime`) and does not touch the
  progress of the regular scraper, so the project keeps being scraped as usual
  while the rescrape runs. The rescrapes are executed by the `RescrapeScheduler`,
  which picks up a new rescrape within a few seconds.

  The priority decides which rescrape the scheduler progresses next, and is
  used by the coinmarketcap rate limiter:
    - :high - served before the regular scraper (which keeps a reserved share)
    - :normal - shares the rate limit with the regular scraper
    - :low - uses only the capacity the regular scraper does not use

  Rescrapes can be created and cancelled via the admin dashboard.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias Sanbase.Repo
  alias Sanbase.Project
  alias Sanbase.Model.LatestCoinmarketcapData

  @priorities [:low, :normal, :high]
  @statuses [:pending, :running, :finished, :failed, :cancelled]
  @active_statuses [:pending, :running]

  schema "schedule_rescrape_prices" do
    belongs_to(:project, Project)
    field(:from, :naive_datetime)
    field(:to, :naive_datetime)
    field(:priority, Ecto.Enum, values: @priorities, default: :normal)
    field(:status, Ecto.Enum, values: @statuses, default: :pending)
    field(:progress_datetime, :naive_datetime)
    field(:last_error, :string)
    field(:started_at, :naive_datetime)
    field(:finished_at, :naive_datetime)

    timestamps()
  end

  def priorities(), do: @priorities
  def statuses(), do: @statuses

  def changeset(srp, attrs \\ %{})

  def changeset(
        %ScheduleRescrapePrice{} = srp,
        %{
          from: %{day: _, hour: _, min: _, month: _, year: _} = from,
          to: %{day: _, hour: _, min: _, month: _, year: _} = to
        } = attrs
      ) do
    {:ok, from} = to_naive(from)
    {:ok, to} = to_naive(to)

    attrs = attrs |> Map.put(:from, from) |> Map.put(:to, to)
    changeset(srp, attrs)
  end

  def changeset(%ScheduleRescrapePrice{} = srp, attrs) do
    srp
    |> cast(attrs, [:project_id, :from, :to, :priority, :status])
    |> validate_required([:project_id, :from, :to, :priority, :status])
    |> validate_from_before_to()
    |> validate_from_not_in_future()
    |> unique_constraint(:project_id,
      name: :schedule_rescrape_prices_one_active_per_project_index,
      message: "already has an active (pending or running) rescrape"
    )
    |> check_constraint(:from, name: :from_before_to, message: "must be before `to`")
  end

  @doc ~s"""
  Used by the generic admin edits. Sets the lifecycle fields when the status
  is changed by hand, like cancel/1 and resume/1 do.
  """
  def update_changeset(%ScheduleRescrapePrice{} = srp, attrs) do
    changeset = changeset(srp, attrs)

    case fetch_change(changeset, :status) do
      {:ok, status} when status in @active_statuses ->
        changeset |> put_change(:finished_at, nil) |> put_change(:last_error, nil)

      {:ok, _status} ->
        put_change(changeset, :finished_at, now())

      :error ->
        changeset
    end
  end

  @spec create(map()) :: {:ok, %ScheduleRescrapePrice{}} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %ScheduleRescrapePrice{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @spec by_id(non_neg_integer()) :: {:ok, %ScheduleRescrapePrice{}} | {:error, String.t()}
  def by_id(id) do
    case Repo.get(ScheduleRescrapePrice, id) |> Repo.preload(:project) do
      %ScheduleRescrapePrice{} = srp -> {:ok, srp}
      nil -> {:error, "Rescrape with id #{id} does not exist"}
    end
  end

  @spec active?(%ScheduleRescrapePrice{}) :: boolean()
  def active?(%ScheduleRescrapePrice{status: status}), do: status in @active_statuses

  @doc ~s"""
  The datetime the next chunk of the rescrape should be fetched from.
  """
  @spec cursor(%ScheduleRescrapePrice{}) :: NaiveDateTime.t()
  def cursor(%ScheduleRescrapePrice{progress_datetime: nil, from: from}), do: from
  def cursor(%ScheduleRescrapePrice{progress_datetime: progress}), do: progress

  # 0 is the highest priority
  @spec priority_rank(%ScheduleRescrapePrice{}) :: non_neg_integer()
  def priority_rank(%ScheduleRescrapePrice{priority: :high}), do: 0
  def priority_rank(%ScheduleRescrapePrice{priority: :normal}), do: 1
  def priority_rank(%ScheduleRescrapePrice{priority: :low}), do: 2

  # The state transitions below are conditional updates, so they never
  # override a rescrape that was cancelled in the meantime, and only one
  # scheduler can move the cursor of a rescrape if two of them run it
  # concurrently (e.g. during a deploy).

  @spec mark_running(%ScheduleRescrapePrice{}) ::
          {:ok, %ScheduleRescrapePrice{}} | {:error, :not_active}
  def mark_running(%ScheduleRescrapePrice{} = srp) do
    started_at = srp.started_at || now()

    conditional_update(srp, active_query(srp),
      status: :running,
      started_at: started_at
    )
  end

  @doc ~s"""
  Move the cursor of the rescrape from `srp.progress_datetime` to `progress`.
  Fails if the rescrape is no longer active or if its cursor was moved by someone else.
  """
  @spec advance_cursor(%ScheduleRescrapePrice{}, NaiveDateTime.t()) ::
          {:ok, %ScheduleRescrapePrice{}} | {:error, :not_active}
  def advance_cursor(%ScheduleRescrapePrice{progress_datetime: expected} = srp, progress) do
    query =
      case expected do
        nil -> active_query(srp) |> where([s], is_nil(s.progress_datetime))
        _ -> active_query(srp) |> where([s], s.progress_datetime == ^expected)
      end

    conditional_update(srp, query,
      progress_datetime: NaiveDateTime.truncate(progress, :second),
      last_error: nil
    )
  end

  def mark_finished(%ScheduleRescrapePrice{} = srp) do
    conditional_update(srp, active_query(srp), status: :finished, finished_at: now())
  end

  def mark_failed(%ScheduleRescrapePrice{} = srp, error) do
    conditional_update(srp, active_query(srp),
      status: :failed,
      finished_at: now(),
      last_error: error_to_string(error)
    )
  end

  def store_error(%ScheduleRescrapePrice{} = srp, error) do
    conditional_update(srp, active_query(srp), last_error: error_to_string(error))
  end

  @doc ~s"""
  Cancel an active rescrape. The scheduler notices the cancellation when it
  moves the cursor or reloads the rescrapes.
  """
  @spec cancel(%ScheduleRescrapePrice{}) ::
          {:ok, %ScheduleRescrapePrice{}} | {:error, :not_active}
  def cancel(%ScheduleRescrapePrice{} = srp) do
    conditional_update(srp, active_query(srp), status: :cancelled, finished_at: now())
  end

  @doc ~s"""
  Move a failed or cancelled rescrape back to pending. The rescrape continues
  from its cursor.
  """
  @spec resume(%ScheduleRescrapePrice{}) ::
          {:ok, %ScheduleRescrapePrice{}} | {:error, Ecto.Changeset.t() | String.t()}
  def resume(%ScheduleRescrapePrice{status: status} = srp) when status in [:failed, :cancelled] do
    srp
    |> changeset(%{status: :pending})
    |> put_change(:finished_at, nil)
    |> put_change(:last_error, nil)
    |> Repo.update()
  end

  def resume(%ScheduleRescrapePrice{}),
    do: {:error, "Only failed or cancelled rescrapes can be resumed"}

  @doc ~s"""
  Change the priority of a rescrape. The scheduler picks it up within a few seconds.
  """
  @spec update_priority(%ScheduleRescrapePrice{}, atom() | String.t()) ::
          {:ok, %ScheduleRescrapePrice{}} | {:error, Ecto.Changeset.t()}
  def update_priority(%ScheduleRescrapePrice{} = srp, priority) do
    srp
    |> changeset(%{priority: priority})
    |> Repo.update()
  end

  @doc ~s"""
  The rescrapes with their projects, the running and pending ones first.

  Options:
    - :status - a status, :active (pending or running) or nil for all
    - :search - a part of the project's slug or name
    - :limit - 200 by default
  """
  @spec list(Keyword.t()) :: [%ScheduleRescrapePrice{}]
  def list(opts \\ []) do
    from(s in ScheduleRescrapePrice,
      join: p in assoc(s, :project),
      as: :project,
      order_by: [
        asc: fragment("CASE ? WHEN 'running' THEN 0 WHEN 'pending' THEN 1 ELSE 2 END", s.status),
        desc: s.id
      ],
      limit: ^Keyword.get(opts, :limit, 200),
      preload: [project: p]
    )
    |> filter_status(Keyword.get(opts, :status))
    |> filter_search(Keyword.get(opts, :search))
    |> Repo.all()
  end

  @doc ~s"""
  The pending and running rescrapes, without their projects.
  """
  @spec list_active() :: [%ScheduleRescrapePrice{}]
  def list_active() do
    from(s in ScheduleRescrapePrice, where: s.status in ^@active_statuses)
    |> Repo.all()
  end

  @doc ~s"""
  The coinmarketcap integer ids of the projects, by project id. The projects
  without one are not in the map.
  """
  @spec coinmarketcap_integer_ids([non_neg_integer()]) :: %{
          non_neg_integer() => non_neg_integer()
        }
  def coinmarketcap_integer_ids(project_ids) do
    from(ssm in Project.SourceSlugMapping,
      join: cmc in LatestCoinmarketcapData,
      on: cmc.coinmarketcap_id == ssm.slug,
      where:
        ssm.source == "coinmarketcap" and ssm.project_id in ^project_ids and
          not is_nil(cmc.coinmarketcap_integer_id),
      select: {ssm.project_id, cmc.coinmarketcap_integer_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  @spec status_counts() :: %{atom() => non_neg_integer()}
  def status_counts() do
    from(s in ScheduleRescrapePrice, group_by: s.status, select: {s.status, count(s.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc ~s"""
  The part of the interval that is already rescraped, between 0 and 1.
  The interval ends at `to`, or at `now` if `to` is in the future.
  """
  @spec progress(%ScheduleRescrapePrice{}, NaiveDateTime.t()) :: float()
  def progress(%ScheduleRescrapePrice{status: :finished}, _now), do: 1.0

  def progress(%ScheduleRescrapePrice{from: from, to: to} = srp, now) do
    total = NaiveDateTime.diff(Enum.min([to, now], NaiveDateTime), from)
    done = NaiveDateTime.diff(cursor(srp), from)

    # A rescrape whose interval starts in the future has nothing done yet
    if total > 0, do: min(max(done / total, 0.0), 1.0), else: 0.0
  end

  @doc ~s"""
  The projects scraped from coinmarketcap whose slug, name or ticker contain
  `search`, ordered by their coinmarketcap rank.
  """
  @spec search_projects(String.t(), non_neg_integer()) :: [map()]
  def search_projects(search, limit) do
    pattern = "%" <> escape_like(search) <> "%"

    cmc_projects_query()
    |> where(
      [p],
      ilike(p.slug, ^pattern) or ilike(p.name, ^pattern) or ilike(p.ticker, ^pattern)
    )
    |> limit(^limit)
    |> Repo.all()
  end

  @doc ~s"""
  The projects scraped from coinmarketcap with the given slugs, ordered by
  their coinmarketcap rank.
  """
  @spec projects_by_slugs([String.t()]) :: [map()]
  def projects_by_slugs(slugs) do
    cmc_projects_query()
    |> where([p], p.slug in ^slugs)
    |> Repo.all()
  end

  def to_naive(%{
        day: day,
        hour: hour,
        min: min,
        month: month,
        year: year
      })
      when is_binary(day) and is_binary(hour) and is_binary(min) and is_binary(month) and
             is_binary(year) do
    [day, hour, min, month, year] =
      [day, hour, min, month, year] |> Enum.map(&String.to_integer/1)

    NaiveDateTime.from_erl({{year, month, day}, {hour, min, 0}})
  end

  # Private functions

  defp active_query(%ScheduleRescrapePrice{id: id}) do
    from(s in ScheduleRescrapePrice, where: s.id == ^id and s.status in ^@active_statuses)
  end

  defp conditional_update(%ScheduleRescrapePrice{} = srp, query, changes) do
    changes = Keyword.put(changes, :updated_at, now())

    case Repo.update_all(query, set: changes) do
      {1, _} -> {:ok, struct!(srp, changes)}
      {0, _} -> {:error, :not_active}
    end
  end

  defp filter_status(query, nil), do: query

  defp filter_status(query, :active),
    do: where(query, [s], s.status in ^@active_statuses)

  defp filter_status(query, status) when status in @statuses,
    do: where(query, [s], s.status == ^status)

  defp filter_search(query, search) when search in [nil, ""], do: query

  defp filter_search(query, search) do
    pattern = "%" <> escape_like(search) <> "%"
    where(query, [project: p], ilike(p.slug, ^pattern) or ilike(p.name, ^pattern))
  end

  defp cmc_projects_query() do
    from(p in Project,
      join: ssm in assoc(p, :source_slug_mappings),
      on: ssm.source == "coinmarketcap",
      left_join: cmc in Sanbase.Model.LatestCoinmarketcapData,
      on: cmc.coinmarketcap_id == ssm.slug,
      order_by: [asc_nulls_last: cmc.rank, asc: p.slug],
      select: %{id: p.id, slug: p.slug, name: p.name, ticker: p.ticker, rank: cmc.rank}
    )
  end

  defp escape_like(string), do: String.replace(string, ~r/[\\%_]/, "\\\\\\0")

  defp validate_from_before_to(changeset) do
    from = get_field(changeset, :from)
    to = get_field(changeset, :to)

    if from && to && NaiveDateTime.compare(from, to) != :lt do
      add_error(changeset, :from, "must be before `to`")
    else
      changeset
    end
  end

  # The scheduler would wait until `from` to start the rescrape
  defp validate_from_not_in_future(changeset) do
    validate_change(changeset, :from, fn :from, from ->
      if NaiveDateTime.compare(from, NaiveDateTime.utc_now()) == :gt,
        do: [from: "must not be in the future"],
        else: []
    end)
  end

  defp error_to_string(error) when is_binary(error), do: String.slice(error, 0, 2000)
  defp error_to_string(error), do: inspect(error, limit: 50) |> String.slice(0, 2000)

  defp now(), do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
end
