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

  @type dashboard_id :: non_neg_integer()

  # Example of a dashboard cache
  # %{
  #   "updated_at" => DateTime.t(),
  #   "data" => %{
  #     "rows" => [String.t()],
  #     "columns" => [String.t()]
  #     "compressed_rows_json" => String.t()
  #   }
  # }
  @type panel_cache :: %{
          String.t() => %{
            String.t() => list(String.t()),
            String.t() => list(String.t() | number() | boolean() | DateTime.t()),
            String.t() => String.t()
          },
          String.t() => DateTime.t() | String.t()
        }

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          dashboard_id: dashboard_id(),
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
    |> maybe_apply_function(&transform_loaded_cache/1)
  end

  @doc ~s"""
  Create a new empty record for the given dashboard_id.
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
  @spec update_panel_cache(non_neg_integer(), String.t(), Dashboad.Query.Result.t()) ::
          {:ok, t()} | {:error, any()}
  def update_panel_cache(dashboard_id, panel_id, query_result) do
    {:ok, cache} = by_dashboard_id(dashboard_id)

    panel_cache = build_panel_cache(query_result)
    panels = Map.update(cache.panels, panel_id, panel_cache, fn _ -> panel_cache end)

    cache
    |> change(%{panels: panels})
    |> Sanbase.Repo.update()
  end

  @doc ~s"""
  Remove the panel result from the cache. This is invoked when the panel is
  removed from the dashboard.
  """
  @spec remove_panel_cache(non_neg_integer(), String.t()) ::
          {:ok, t()} | {:error, any()}
  def remove_panel_cache(dashboard_id, panel_id) do
    {:ok, cache} = by_dashboard_id(dashboard_id)
    panels = Enum.reject(cache.panels, &(&1.id == panel_id))

    cache
    |> change(%{panels: panels})
    |> Sanbase.Repo.update()
  end

  # Private functions

  defp build_panel_cache(query_result) do
    %{
      data: %{
        columns: query_result.columns,
        compressed_rows_json: query_result.compressed_rows_json |> Base.encode64()
      },
      updated_at: DateTime.utc_now()
    }
  end

  defp transform_loaded_cache(%__MODULE__{} = cache) do
    panels =
      cache.panels
      |> Map.new(fn {panel_id, panel_cache} ->
        %{
          "data" => %{"columns" => columns, "compressed_rows_json" => compressed_rows_json},
          "updated_at" => updated_at
        } = panel_cache

        rows =
          compressed_rows_json
          |> Base.decode64!()
          |> :zlib.gunzip()
          |> Jason.decode!()

        {:ok, updated_at, _} = DateTime.from_iso8601(updated_at)
        {:ok, rows} = transform_cache_rows(rows)

        panel_cache =
          panel_cache
          |> put_in(["data", "rows"], rows)
          |> put_in(["data", "compressed_rows_json"], compressed_rows_json)
          |> put_in(["data", "columns"], columns)
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
