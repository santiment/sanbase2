defmodule SanbaseWeb.Graphql.Resolvers.CommentEntityIdResolver do
  import Absinthe.Resolution.Helpers, except: [async: 1]
  alias SanbaseWeb.Graphql.SanbaseDataloader

  def insight_id(%Sanbase.Comment{id: id}, _args, %{context: %{loader: loader}}) do
    get_dataloader_comment_entity_id(loader, :comment_insight_id, id)
  end

  def timeline_event_id(%Sanbase.Comment{id: id}, _args, %{context: %{loader: loader}}) do
    get_dataloader_comment_entity_id(loader, :comment_timeline_event_id, id)
  end

  def blockchain_address_id(%Sanbase.Comment{id: id}, _args, %{context: %{loader: loader}}) do
    get_dataloader_comment_entity_id(loader, :comment_blockchain_address_id, id)
  end

  def proposal_id(%Sanbase.Comment{id: id}, _args, %{context: %{loader: loader}}) do
    get_dataloader_comment_entity_id(loader, :comment_wallet_hunter_proposal_id, id)
  end

  def short_url_id(%Sanbase.Comment{id: id}, _args, %{context: %{loader: loader}}) do
    get_dataloader_comment_entity_id(loader, :comment_short_url_id, id)
  end

  def watchlist_id(%Sanbase.Comment{id: id}, _args, %{context: %{loader: loader}}) do
    get_dataloader_comment_entity_id(loader, :comment_watchlist_id, id)
  end

  def chart_configuration_id(%Sanbase.Comment{id: id}, _args, %{context: %{loader: loader}}) do
    get_dataloader_comment_entity_id(loader, :comment_chart_configuration_id, id)
  end

  defp get_dataloader_comment_entity_id(loader, entity_id_name, id) do
    loader
    |> Dataloader.load(SanbaseDataloader, entity_id_name, id)
    |> on_load(fn loader ->
      {:ok, Dataloader.get(loader, SanbaseDataloader, entity_id_name, id)}
    end)
  end
end
