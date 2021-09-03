defmodule Sanbase.BlockchainAddress.BlockchainAddressLabelChange.SqlQuery do
  def labels_list_query() do
    query = """
    SELECT fqn, display_name
    FROM label_metadata FINAL
    """

    args = []

    {query, args}
  end

  def label_changes_query(address, blockchain, from, to) do
    query = """
    SELECT
      toUnixTimestamp(dt),
      address,
      dictGetString('default.labels_dict', 'fqn', label_id) AS label_fqn,
      sign
    FROM address_label_changes
    PREWHERE
      address = ?1 AND
      blockchain = ?2 AND
      dt >= toDateTime(?3) AND
      dt < toDateTime(?4)
    """

    args = [address, blockchain, DateTime.to_unix(from), DateTime.to_unix(to)]

    {query, args}
  end
end
