defmodule Sanbase.ExternalServices.Coinmarketcap.ProBackfill.Run do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias __MODULE__

  @statuses ~w(pending running paused completed failed canceled)
  @scopes ~w(single all list)
  @usage_precisions ~w(exact estimated mixed)

  schema "coinmarketcap_pro_backfill_runs" do
    field(:source, :string)
    field(:scope, :string)
    field(:status, :string)
    field(:interval, :string)
    field(:time_start, :utc_datetime)
    field(:time_end, :utc_datetime)
    field(:dry_run, :boolean, default: false)
    field(:total_assets, :integer, default: 0)
    field(:done_assets, :integer, default: 0)
    field(:failed_assets, :integer, default: 0)
    field(:pending_assets, :integer, default: 0)
    field(:api_credits_used_total, :float, default: 0.0)
    field(:api_calls_total, :integer, default: 0)
    field(:rate_limited_calls_total, :integer, default: 0)
    field(:usage_precision, :string, default: "exact")
    field(:last_error, :string)
    field(:started_at, :utc_datetime)
    field(:finished_at, :utc_datetime)

    has_many(:assets, Sanbase.ExternalServices.Coinmarketcap.ProBackfill.Asset,
      foreign_key: :run_id
    )

    timestamps()
  end

  def changeset(%Run{} = run, attrs) do
    run
    |> cast(attrs, [
      :source,
      :scope,
      :status,
      :interval,
      :time_start,
      :time_end,
      :dry_run,
      :total_assets,
      :done_assets,
      :failed_assets,
      :pending_assets,
      :api_credits_used_total,
      :api_calls_total,
      :rate_limited_calls_total,
      :usage_precision,
      :last_error,
      :started_at,
      :finished_at
    ])
    |> validate_required([:scope, :status, :interval, :time_start, :time_end, :source])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:scope, @scopes)
    |> validate_inclusion(:usage_precision, @usage_precisions)
  end

  def create(attrs) do
    %Run{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def get(id), do: Repo.get(Run, id)

  def get!(id), do: Repo.get!(Run, id)

  def list(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    from(r in Run, order_by: [desc: r.inserted_at], limit: ^limit)
    |> Repo.all()
  end

  def update_run(%Run{} = run, attrs) do
    run
    |> changeset(attrs)
    |> Repo.update()
  end

  def mark_running(%Run{} = run) do
    attrs = %{status: "running", started_at: run.started_at || DateTime.utc_now()}
    update_run(run, attrs)
  end

  def mark_paused(%Run{} = run), do: update_run(run, %{status: "paused"})

  def mark_canceled(%Run{} = run),
    do: update_run(run, %{status: "canceled", finished_at: DateTime.utc_now()})

  def mark_failed(%Run{} = run, error) do
    update_run(run, %{status: "failed", last_error: error, finished_at: DateTime.utc_now()})
  end

  def maybe_mark_completed(%Run{} = run) do
    if run.total_assets > 0 and run.done_assets + run.failed_assets >= run.total_assets do
      update_run(run, %{status: "completed", finished_at: DateTime.utc_now()})
    else
      {:ok, run}
    end
  end

  def increment_stats(run_id, stats) when is_map(stats) do
    query = from(r in Run, where: r.id == ^run_id)

    inc_values =
      stats
      |> Map.take([
        :done_assets,
        :failed_assets,
        :pending_assets,
        :api_credits_used_total,
        :api_calls_total,
        :rate_limited_calls_total
      ])
      |> Enum.reject(fn {_k, v} -> v == 0 end)

    set_values =
      stats
      |> Map.take([:usage_precision, :last_error, :status, :finished_at, :started_at])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    opts =
      []
      |> maybe_put_update_opt(:inc, inc_values)
      |> maybe_put_update_opt(:set, set_values)

    case opts do
      [] -> {0, nil}
      _ -> Repo.update_all(query, opts)
    end
  end

  defp maybe_put_update_opt(opts, _key, []), do: opts
  defp maybe_put_update_opt(opts, key, values), do: Keyword.put(opts, key, values)
end
