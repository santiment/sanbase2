defmodule SanbaseWeb.Graphql.MetricshubDataloader do
  alias Sanbase.SocialData.SocialDocument

  # No internal `Parallel.map` fan-out — ctx is already in
  # `Logger.metadata` for this Dataloader.KV task (re-seeded in
  # `SanbaseDataloader.make_kv_fun/1`), so `SocialDocument.get_documents/1`
  # picks up `activity_traces_hidden` via `RequestContext.current/0`.
  def query(:social_documents_by_ids, data, _ctx) do
    top_documents_ids =
      data |> Enum.to_list() |> List.flatten() |> Enum.uniq()

    # The loaded ids are LISTS of document ids, but the result map is keyed by
    # the individual document id, so the central nil-filling in
    # SanbaseDataloader.to_total_result_map/2 cannot make this map total —
    # fill the individual document ids here instead.
    case SocialDocument.get_documents(top_documents_ids) do
      {:ok, list} ->
        map = Map.new(list, fn %SocialDocument{document_id: id} = struct -> {id, struct} end)
        Enum.reduce(top_documents_ids, map, fn id, acc -> Map.put_new(acc, id, nil) end)

      {:error, error} ->
        Map.new(top_documents_ids, fn id -> {id, {:error, error}} end)
    end
  end
end
