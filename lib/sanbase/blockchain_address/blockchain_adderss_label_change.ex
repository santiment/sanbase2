defmodule Sanbase.BlockchainAddress.BlockchainAddressLabelChange do
  alias Sanbase.ClickhouseRepo

  def label_changes(address, infrastructure, from, to) do
    blockchain = Sanbase.Model.Project.infrastructure_to_blockchain(infrastructure)
    address = Sanbase.BlockchainAddress.to_internal_format(address)

    {query, args} = label_changes_query(address, blockchain, from, to)

    ClickhouseRepo.query_transform(query, args, fn [unix, address, label_key, label_value, sign] ->
      label = if label_value != "", do: "#{label_key}/#{label_value}", else: label_key

      %{
        datetime: DateTime.from_unix!(unix),
        address: address,
        label: label,
        sign: sign
      }
    end)
  end

  defp label_changes_query(address, blockchain, from, to) do
    query = """
    SELECT
      toUnixTimestamp(dt),
      address,
      dictGetString('default.labels_dict', 'key', label_id) AS label_key,
      dictGetString('default.labels_dict', 'value', label_id) AS label_value,
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
