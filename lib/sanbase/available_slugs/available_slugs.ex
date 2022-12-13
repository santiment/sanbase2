defmodule Sanbase.AvailableSlugs do
  @moduledoc ~s"""
  Module for fast checking if a slug is existing.

  The slugs are stored in an ETS table and the check is done via :ets.lookup/2.
  This is faster than caching all slugs, retrieving them in the caller process and
  checking if the slug is in the list.
  """
  @behaviour Sanbase.AvailableSlugs.Behaviour

  # There are 2 special cases that are not a project slug but refer to big groups
  # of projects and there is marketcap and volume data for them
  @non_project_slugs ["TOTAL_MARKET", "TOTAL_ERC20"]

  @ets_table :available_projects_slugs_ets_table
  use GenServer

  @impl Sanbase.AvailableSlugs.Behaviour
  def valid_slug?(slug) do
    case :ets.lookup(@ets_table, slug) do
      [] -> slug in @non_project_slugs
      _ -> true
    end
  end

  ### Internals

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(_opts) do
    ets_table = :ets.new(@ets_table, [:set, :protected, :named_table, read_concurrency: true])
    initial_state = %{ets_table: ets_table}

    {:ok, initial_state, {:continue, :initialize}}
  end

  @impl true
  def handle_continue(:initialize, state) do
    Process.send_after(self(), :refill_slugs, 10 * 60 * 1000)
    {:noreply, refill_slugs(state)}
  end

  @impl true
  def handle_info(:refill_slugs, state) do
    Process.send_after(self(), :refill_slugs, 10 * 60 * 1000)
    {:noreply, refill_slugs(state)}
  end

  @non_project_slugs ["gold", "s-and-p-500", "crude-oil", "dxy"]
  defp refill_slugs(state) do
    %{ets_table: ets_table} = state

    slugs =
      @non_project_slugs ++
        Sanbase.Project.List.projects_slugs(include_hidden: true)

    ets_slugs = :ets.tab2list(ets_table) |> Enum.map(&elem(&1, 0))
    slugs_to_remove = ets_slugs -- slugs
    slugs_to_add = slugs -- ets_slugs

    slugs_to_remove |> Enum.each(fn slug -> :ets.delete(ets_table, slug) end)
    slugs_to_add |> Enum.each(fn slug -> :ets.insert(ets_table, {slug, true}) end)

    state
  end
end
