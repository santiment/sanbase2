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
  @group_of_slugs ["TOTAL_MARKET", "TOTAL_ERC20"]
  @non_project_slugs ~w(s-and-p-500 gold crude-oil dxy gbtc ibit fbtc arkb btco bitb hodl m2-money)

  def non_project_slugs(), do: @non_project_slugs
  @ets_table :available_projects_slugs_ets_table
  use GenServer

  @impl Sanbase.AvailableSlugs.Behaviour
  def valid_slug?(slug, retries \\ 5) do
    if :ets.whereis(@ets_table) == :undefined do
      if retries > 0 do
        Process.sleep(200 * round(:math.pow(2, 5 - retries)))
        valid_slug?(slug, retries - 1)
      else
        # Fallback to static lists if table still isn't available after retries
        slug in @non_project_slugs or slug in @group_of_slugs
      end
    else
      case :ets.lookup(@ets_table, slug) do
        [] -> slug in @non_project_slugs or slug in @group_of_slugs
        _ -> true
      end
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

  defp refill_slugs(state) do
    %{ets_table: ets_table} = state

    slugs =
      @non_project_slugs ++
        @group_of_slugs ++
        Sanbase.Project.List.projects_slugs(include_hidden: true)

    ets_slugs = :ets.tab2list(ets_table) |> Enum.map(&elem(&1, 0))
    slugs_to_remove = ets_slugs -- slugs
    slugs_to_add = slugs -- ets_slugs

    slugs_to_remove |> Enum.each(fn slug -> :ets.delete(ets_table, slug) end)
    slugs_to_add |> Enum.each(fn slug -> :ets.insert(ets_table, {slug, true}) end)

    state
  end
end
