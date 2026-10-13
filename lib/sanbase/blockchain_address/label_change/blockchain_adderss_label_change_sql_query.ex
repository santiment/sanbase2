defmodule Sanbase.BlockchainAddress.BlockchainAddressLabelChange.SqlQuery do
  def labels_list_query() do
    sql = """
    SELECT fqn, display_name
    FROM label_metadata FINAL
    """

    Sanbase.Clickhouse.Query.new(sql, %{})
  end
end
