defmodule Sanbase.Repo.Migrations.AddMoreMarketSegments do
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Project
  alias Sanbase.Model.MarketSegment

  def up do
    setup()

    # Get all Projects
    projects = get_projects()

    # Create a market segment for every infrastructure and get a map from
    # the infrastructure to the market segment ID
    infrastrucutre_to_segment_id = infrastrucutre_to_segment_id(projects)

    # Add a new market segment for every project that is showing the infrastructure
    # on which it is building
    insert_data =
      projects
      |> Enum.map(fn
        %{id: id, infrastructure: %{code: code}} when not is_nil(code) ->
          %{
            project_id: id,
            market_segment_id: Map.get(infrastrucutre_to_segment_id, code)
          }

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil/1)

    # Insert the new market segments, ignoring duplicates
    Sanbase.Repo.insert_all(Project.ProjectMarketSegment, insert_data, on_conflict: :nothing)
  end

  def down, do: :ok

  defp get_projects() do
    Project.List.projects() |> Sanbase.Repo.preload([:infrastructure, :market_segments])
  end

  defp infrastrucutre_to_segment_id(projects) do
    # Map all the available infrastructures as tickers from prod to the corresponding
    # project name. Example: BTC -> Bitcoin, EOS -> EOS, ETH -> Ethereum, etc.
    infrastrucutre_to_segment =
      Enum.zip(
        ~w(BTC EOS ETC ETH IOTA NEO NXT OMNI UBQ WAVES XCP XEM),
        ~w(Bitcoin EOS Ethereum-Classic Ethereum IOTA Neo Nxt Omni Ubiq Waves Counterparty NEM)
      )
      |> Map.new()

    # The infrastructures that are already names, not tickers, are taken as they are
    infrastrucutre_to_segment =
      ~w(Achain Ardor Binance Bitshares Graphene Komodo Nebulas Qtum Scrypt Steem Stellar Tron)
      |> Enum.reduce(infrastrucutre_to_segment, fn name, acc ->
        Map.put(acc, name, name)
      end)

    # Get the final market segments names that should be used
    market_segment_names = infrastrucutre_to_segment |> Map.values()

    # Insert all the new market segments, doing nothing if the segment already exists
    insert_data = market_segment_names |> Enum.map(fn segment -> %{name: segment} end)
    Sanbase.Repo.insert_all(MarketSegment, insert_data, on_conflict: :nothing)

    # Fetch all market segments that we inserted above so we can get their IDs
    market_segments =
      from(ms in MarketSegment,
        where: ms.name in ^market_segment_names
      )
      |> Sanbase.Repo.all()

    # Map an infrastructure to the corresponding ID. The name is always equal to
    # the value, i.e. the name. The key is either the name or the ticker
    infrastrucutre_to_segment
    |> Enum.map(fn {k, v} ->
      segment = Enum.find(market_segments, fn %{name: name} -> name == v || name == k end)
      {k, segment.id}
    end)
    |> Map.new()
  end

  defp setup() do
    Application.ensure_all_started(:tzdata)
  end
end
