defmodule Sanbase.BlockchainAddress.BlockchainAddressLabelChange do
  import __MODULE__.SqlQuery
  alias Sanbase.ClickhouseRepo

  def labels_list() do
    query_struct = labels_list_query()

    ClickhouseRepo.query_transform(query_struct, fn
      [label_fqn, display_name] ->
        origin = String.split(label_fqn, "/") |> List.first()
        %{name: label_fqn, human_readable_name: display_name, origin: origin}
    end)
  end

  def label_changes(address, infrastructure, from, to) do
    blockchain = Sanbase.Project.infrastructure_to_blockchain(infrastructure)
    address = Sanbase.BlockchainAddress.to_internal_format(address)

    query_struct = label_changes_query(address, blockchain, from, to)

    ClickhouseRepo.query_transform(query_struct, fn [unix, address, label_fqn, sign] ->
      %{
        datetime: DateTime.from_unix!(unix),
        address: address,
        label: label_fqn,
        sign: sign
      }
    end)
  end
end
