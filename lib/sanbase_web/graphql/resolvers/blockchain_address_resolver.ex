defmodule SanbaseWeb.Graphql.Resolvers.BlockchainAddressResolver do
  require Logger

  import Absinthe.Resolution.Helpers, except: [async: 1]

  alias Sanbase.BlockchainAddress
  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias Sanbase.Utils.ErrorHandling

  def blockchain_address(_root, %{selector: %{id: id}}, _resolution) do
    BlockchainAddress.by_id(id)
  end

  def blockchain_address(
        _root,
        %{selector: %{address: address, infrastructure: infrastructure}},
        _resolution
      ) do
    [%{id: infrastructure_id}] = Sanbase.Model.Infrastructure.by_codes(infrastructure)

    BlockchainAddress.maybe_create(%{address: address, infrastructure_id: infrastructure_id})
    |> case do
      {:ok, addr} ->
        {:ok, addr}

      {:error, changeset} ->
        reason = ErrorHandling.changeset_errors_to_str(changeset)
        {:error, "Cannot get blockchain address #{infrastructure} #{address}. Reason: #{reason}"}
    end
  end

  def blockchain_address_id(%{id: id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :comment_blockchain_address_id, id)
    |> on_load(fn loader ->
      {:ok, Dataloader.get(loader, SanbaseDataloader, :comment_blockchain_address_id, id)}
    end)
  end

  def comments_count(%{id: id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :blockchain_addresses_comments_count, id)
    |> on_load(fn loader ->
      {:ok,
       Dataloader.get(loader, SanbaseDataloader, :blockchain_addresses_comments_count, id) || 0}
    end)
  end
end
