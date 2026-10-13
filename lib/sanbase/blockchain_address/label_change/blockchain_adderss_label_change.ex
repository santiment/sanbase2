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
end
