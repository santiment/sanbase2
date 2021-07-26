defmodule Sanbase.Repo.Migrations.FillMarketSegmentsType do
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Model.MarketSegment

  def up do
    setup()

    infrastructural_market_segments = infrastructural_market_segments()

    from(
      ms in MarketSegment,
      where: ms.name in ^infrastructural_market_segments
    )
    |> Sanbase.Repo.update_all(set: [type: "Infrastructure"])
  end

  def down do
    :ok
  end

  defp setup() do
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:prometheus_ecto)
    Sanbase.Prometheus.EctoInstrumenter.setup()
  end

  defp infrastructural_market_segments() do
    ~w(Bitcoin EOS Ethereum-Classic Ethereum IOTA Neo Nxt Omni Ubiq Waves Counterparty NEM
    Achain Ardor Binance Bitshares Graphene Komodo Nebulas Qtum Scrypt Steem Stellar Tron)
  end
end
