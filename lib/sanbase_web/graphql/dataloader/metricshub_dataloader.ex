defmodule SanbaseWeb.Graphql.MetricshubDataloader do
  alias Sanbase.SocialData.SocialDocument

  def data() do
    Dataloader.KV.new(&query/2)
  end

  def query(:social_documents_by_ids, data) do
    top_documents_ids =
      data |> Enum.to_list() |> List.flatten() |> Enum.uniq()

    {:ok, list} = SocialDocument.get_documents(top_documents_ids)

    Map.new(list, fn %SocialDocument{document_id: id} = struct -> {id, struct} end)
  end
end
