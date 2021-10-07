defmodule SanbaseWeb.Graphql.TransactionTypes do
  use Absinthe.Schema.Notation

  enum :transaction_type do
    value(:in)
    value(:out)
    value(:all)
  end

  object :address do
    field(:address, :string)
    field(:is_exchange, :boolean)
    field(:labels, list_of(:label), default_value: [])
  end

  object :label do
    field(:name, :string)
    field(:origin, :string, default_value: "santiment")
    field(:metadata, :json, default_value: %{})
  end

  object :transaction do
    field(:datetime, non_null(:datetime))
    field(:trx_hash, non_null(:string))
    field(:trx_value, non_null(:float))
    field(:from_address, :address)
    field(:to_address, :address)
    field(:project, :project)
    # Remove when frontend migrates
    field(:slug, :string)
  end

  object :exchange_funds_flow do
    field(:datetime, non_null(:datetime))
    field(:in_out_difference, non_null(:float))
  end
end
