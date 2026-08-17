defmodule Sanbase.AvailableSlugs do
  @moduledoc ~s"""
  Module for fast checking if a slug is existing.

  The slugs are stored in an ETS table and the check is done via :ets.lookup/2.
  This is faster than caching all slugs, retrieving them in the caller process and
  checking if the slug is in the list.
  """
  @behaviour Sanbase.AvailableSlugs.Behaviour

  # There are special cases that are not a project slug but refer to big groups
  # of projects and there is marketcap and volume data for them
  # TOTAL_MARKET comes from cmc, total_market is our own creation, they are different
  @group_of_slugs [
    "TOTAL_MARKET",
    "total_market",
    "total_market_2",
    "total_market_3",
    "crypto_market",
    "TOTAL_ERC20"
  ]

  # Predate the `non_crypto_assets` table. New non-crypto assets go there, not here.
  @legacy_non_project_slugs ~w(s-and-p-500 gold silver crude-oil dxy gbtc ibit fbtc arkb btco bitb hodl m2-money)

  def non_project_slugs() do
    (@legacy_non_project_slugs ++ Sanbase.NonCryptoAsset.slugs(include_hidden: true))
    |> Enum.uniq()
  end

  @ets_table :available_projects_slugs_ets_table
  use GenServer

  @impl Sanbase.AvailableSlugs.Behaviour
  def valid_slug?(slug, retries \\ 5) do
    if :ets.whereis(@ets_table) == :undefined do
      if retries > 0 do
        Process.sleep(200 * round(:math.pow(2, 5 - retries)))
        valid_slug?(slug, retries - 1)
      else
        # Fallback to the static lists if table still isn't available after retries
        static_slug?(slug)
      end
    else
      case :ets.lookup(@ets_table, slug) do
        [] -> static_slug?(slug)
        _ -> true
      end
    end
  end

  @doc ~s"""
  Check if the slug is a non-crypto asset - stock, commodity, index, ETF, etc.
  """
  def non_crypto_asset_slug?(slug) do
    if :ets.whereis(@ets_table) == :undefined do
      # No table - the test env, where the GenServer is not started, or a call
      # racing the first fill. Everywhere else this is a single ETS lookup.
      slug in @legacy_non_project_slugs or Sanbase.NonCryptoAsset.id_by_slug(slug) != nil
    else
      match?([{_slug, :non_crypto_asset}], :ets.lookup(@ets_table, slug))
    end
  end

  defp static_slug?(slug), do: slug in @group_of_slugs or slug in @legacy_non_project_slugs

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

    # The kind is stored next to the slug so that a caller interested only in the
    # non-crypto assets does a single ETS lookup, too.
    entries =
      tag(@group_of_slugs, :group_of_slugs) ++
        tag(non_project_slugs(), :non_crypto_asset) ++
        tag(project_slugs(), :project)

    ets_entries = :ets.tab2list(ets_table)

    (ets_entries -- entries) |> Enum.each(fn {slug, _kind} -> :ets.delete(ets_table, slug) end)
    (entries -- ets_entries) |> Enum.each(fn entry -> :ets.insert(ets_table, entry) end)

    state
  end

  defp tag(slugs, kind), do: Enum.map(slugs, &{&1, kind})

  defp project_slugs(), do: Sanbase.Project.List.projects_slugs(include_hidden: true)
end
