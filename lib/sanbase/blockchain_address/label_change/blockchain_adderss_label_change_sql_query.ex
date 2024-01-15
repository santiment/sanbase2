defmodule Sanbase.BlockchainAddress.BlockchainAddressLabelChange.SqlQuery do
  def labels_list_query() do
    sql = """
    SELECT fqn, display_name
    FROM label_metadata FINAL
    """

    Sanbase.Clickhouse.Query.new(sql, %{})
  end

  def label_changes_query(address, blockchain, from, to) do
    sql = """
    SELECT
      toUnixTimestamp(dt),
      address,
      dictGetString('default.labels', 'fqn', label_id) AS label_fqn,
      sign
    FROM address_label_changes
    PREWHERE
      address = {{address}} AND
      blockchain = {{blockchain}} AND
      dt >= toDateTime({{from}}) AND
      dt < toDateTime({{to}})
    """

    params = %{
      address: address,
      blockchain: blockchain,
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end
end
