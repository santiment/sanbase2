defmodule Sanbase.Dashboard.Cache do
  @moduledoc ~s"""
  Holds the last computed result of dashboards.

  The cache is the dynamic part of the dashboard as the result of execution
  of the SQL can change on every run. Dashboards can be slow to compute or
  can be viewed by many users. Because of this, a cached version is kept in
  the database and is shown to the users.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]

  @type panel_cache :: %{
          # "data" key
          String.t() => %{
            # "columns" key
            String.t() => list(String.t()),
            # "rows" key
            String.t() => list(String.t() | number() | boolean() | DateTime.t()),
            # "rows_json" key
            String.t() => String.t()
          },
          #  "updated_at" key
          String.t() => DateTime.t() | String.t()
        }

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          dashboard_id: non_neg_integer(),
          panels: %{
            # the key is panel_id
            optional(String.t()) => panel_cache()
          }
        }

  schema "dashboards_cache" do
    field(:dashboard_id, :integer)
    field(:panels, :map, default: %{})

    timestamps()
  end

  @doc ~s"""
  Fetch the cache for the given dashboard
  """
  @spec by_dashboard_id(non_neg_integer()) :: {:ok, t()} | {:error, any()}
  def by_dashboard_id(dashboard_id) do
    case Sanbase.Repo.get_by(__MODULE__, dashboard_id: dashboard_id) do
      nil -> new(dashboard_id)
      %__MODULE__{} = cache -> {:ok, cache}
    end
    |> maybe_apply_function(&transform_cache/1)
  end

  @doc ~s"""
  Create a new empty record for the given dashboard_id
  """

  @spec new(non_neg_integer()) :: {:ok, t()} | {:error, any()}
  def new(dashboard_id) do
    %__MODULE__{}
    |> change(%{dashboard_id: dashboard_id})
    |> Sanbase.Repo.insert()
  end

  @doc ~s"""
  Update the dashboard's panel cache with the provided result.
  """
  @spec update_panel_result(non_neg_integer(), String.t(), map()) ::
          {:ok, t()} | {:error, any()}
  def update_panel_result(dashboard_id, panel_id, result) do
    {:ok, cache} = by_dashboard_id(dashboard_id)

    panel = %{data: result, updated_at: DateTime.utc_now()}
    panels = Map.update(cache.panels, panel_id, panel, fn _ -> panel end)

    cache
    |> change(%{panels: panels})
    |> Sanbase.Repo.update()
  end

  @doc ~s"""
  Remove the panel result from the cache. This is invoked when the panel is
  removed from the dashboard.
  """
  @spec remove_panel_result(non_neg_integer(), String.t()) ::
          {:ok, t()} | {:error, any()}
  def remove_panel_result(dashboard_id, panel_id) do
    {:ok, cache} = by_dashboard_id(dashboard_id)
    panels = Enum.reject(cache.panels, &(&1.id == panel_id))

    cache
    |> change(%{panels: panels})
    |> Sanbase.Repo.update()
  end

  # Private functions

  defp transform_cache(%__MODULE__{} = cache) do
    panels =
      cache.panels
      |> Map.new(fn {panel_id, panel_cache} ->
        %{"data" => %{"rows" => rows}, "updated_at" => updated_at} = panel_cache
        {:ok, updated_at, _} = DateTime.from_iso8601(updated_at)
        {:ok, rows} = transform_cache_rows(rows)

        panel_cache =
          panel_cache
          |> put_in(["data", "rows"], rows)
          |> put_in(["updated_at"], updated_at)

        {panel_id, panel_cache}
      end)

    %{cache | panels: panels}
  end

  # Transform the rows of the panel cache. Transformations applied:
  # 1. Transform ISO8601 datetimes to DateTime objects
  defp transform_cache_rows(rows) do
    transformed_rows =
      rows
      |> Enum.map(fn row ->
        row
        |> Enum.map(fn
          elem when is_binary(elem) ->
            case DateTime.from_iso8601(elem) do
              {:ok, datetime, _} -> datetime
              _ -> elem
            end

          elem ->
            elem
        end)
      end)

    {:ok, transformed_rows}
  end
end
