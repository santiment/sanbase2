defmodule Sanbase.BlockchainAddress.BlockchainAddressUserPairLabel do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.BlockchainAddress

  schema "blockchain_address_user_pairs_labels" do
    belongs_to(:blockchain_address_user_pair, BlockchainAddress.BlockchainAddressUserPair)
    belongs_to(:label, BlockchainAddress.BlockchainAddressLabel)
  end

  def changeset(post_tag, attrs \\ %{}) do
    post_tag
    |> cast(attrs, [:blockchain_address_user_pair_id, :label_id])
    |> validate_required([:blockchain_address_user_pair_id, :label_id])
  end
end

defmodule SanbaseWeb.ExAdmin.BlockchainAddressUserPairLabel do
  use ExAdmin.Register

  import Ecto.Query

  register_resource Sanbase.BlockchainAddress.BlockchainAddressUserPairLabel do
    controller do
      after_filter(:set_defaults, only: [:new])
    end
  end

  def set_defaults(conn, params, resource, :new) do
    {conn, params, resource |> set_post_default(params)}
  end

  defp set_post_default(%{blockchain_address_user_pair_id: nil} = args, params) do
    Map.get(params, :blockchain_address_user_pair_id, nil)
    |> case do
      nil ->
        args

      blockchain_address_user_pair_id ->
        Map.put(args, :blockchain_address_user_pair_id, blockchain_address_user_pair_id)
    end
  end
end
