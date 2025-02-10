defmodule SanbaseWeb.Graphql.BlockchainTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  object :blockchain_metadata do
    field(:blockchain, non_null(:string))
    field(:slug, non_null(:string))
    field(:infrastructure, non_null(:string))
    field(:created_on, :datetime)

    # Metrics

    @desc """
    Exchange Metrics are those metrics that are computed by using both raw
    on-chain data complimented by a labeled set of known exchange addresses. The
    exchange addresses cannot be all known, so these metrics are always showing
    an approximation of the real world. Exchange addresses are gathered by ...
    """
    field(:has_exchange_metrics, :boolean)

    @desc """
    (NOTE: How does these differ from the exchange metrics? both need some labeles
    but some labels are harder to obtain than other, so just `label` metrics won't do it)
    Label Metrics are those metrics that are computed by using both raw on-chain
    data complimented by a labeled set of addresses. The labels
    """
    field(:has_label_metrics, :boolean)

    @desc """
    Top holders metrics are those metrics that show the current and historical
    ranking of addresses according to the amount of coins/tokens they hold.
    """
    field(:has_top_holders_metrics, :boolean)

    @desc """
    Exchange top holders metrics are those metrics that need both exchange address
    labels and top holders metrics.
    Examples for such metrics are `Amount held by top N exchange top holders` and
    `Amount held by top N non-exchange top holders`.
    """
    field(:has_exchange_top_holders_metrics, :boolean)

    @desc """
    On-Chain Financial metrics are those metrics that are computed by using both
    raw on-chain data as well as financial data (price, marketcap or trading volume).
    Examples for such metrics are MVRV and NVT.
    """
    field(:has_onchain_financial_metrics, :boolean)

    @desc """
    Pure on-chain metrics are those metrics that are computed by using only raw
    on-chain data. These metrics do not need any additional data to be known in
    order to be computed.
    Examples for such metrics are Transaction Volume and Daily Active Addresses.
    """
    field(:has_pure_onchain_metrics, :boolean)

    @desc """
    Miners metrics are those metrics that show some statistics about on-chain
    miners.
    """
    field(:has_miners_metrics, :boolean)

    @desc """
    Balance metrics are those metrics that are showing the current and historical
    balances of different addresses and assets.
    """
    field(:has_balance_metrics, :boolean)
  end
end
