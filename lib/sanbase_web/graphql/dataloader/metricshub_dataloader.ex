defmodule SanbaseWeb.Graphql.MetricshubDataloader do
  alias Sanbase.SocialData.SocialDocument

  # No internal `Parallel.map` fan-out — ctx is already in
  # `Logger.metadata` for this Dataloader.KV task (re-seeded in
  # `SanbaseDataloader.make_kv_fun/1`), so `SocialDocument.get_documents/1`
  # picks up `activity_traces_hidden` via `RequestContext.current/0`.
  def query(:social_documents_by_ids, data, _ctx) do
    top_documents_ids =
      data |> Enum.to_list() |> List.flatten() |> Enum.uniq()

    case SocialDocument.get_documents(top_documents_ids) do
      {:ok, list} ->
        Map.new(list, fn %SocialDocument{document_id: id} = struct -> {id, struct} end)

      {:error, error} ->
        Map.new(top_documents_ids, fn id -> {id, {:error, error}} end)
    end
  end
end
