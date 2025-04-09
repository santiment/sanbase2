defmodule Sanbase.SocialData.SocialDocument do
  alias Sanbase.Utils.Config

  defstruct [:document_id, :screen_name, :text, :source, :document_url]

  def get_documents(document_ids, source \\ nil) do
    source = source || "reddit,twitter_crypto,telegram,4chan"
    url = "#{metrics_hub_url()}/receive_documents"

    req = Req.new(base_url: url)

    result =
      Req.get(req,
        params: [
          source: source,
          fields: ["text", "screen_name", "source", "link_url"] |> Enum.join(","),
          ids: document_ids |> Enum.map(&to_string/1) |> Enum.join(",")
        ]
      )

    handle_result(result)
  end

  ## Private functions
  defp handle_result({:ok, response}) do
    with %{body: %{"data" => json_data}} when is_binary(json_data) <- response,
         {:ok, data} when is_list(data) <- Jason.decode(json_data) do
      result =
        Enum.map(
          data,
          fn map ->
            %__MODULE__{
              document_id: Map.get(map, "doc_id"),
              screen_name: Map.get(map, "screen_name"),
              text: Map.get(map, "text"),
              source: Map.get(map, "index") |> index_to_source(),
              document_url: Map.get(map, "link_url")
            }
            |> maybe_reconstruct_url()
          end
        )

      {:ok, result}
    end
  end

  defp handle_result({:error, error}) do
    {:error, error}
  end

  defp maybe_reconstruct_url(%__MODULE__{source: "twitter"} = struct) do
    # In case of twitter the URL is not provided, but we can reconstruct it
    %{
      struct
      | document_url: "https://x.com/#{struct.screen_name}/status/#{struct.document_id}"
    }
  end

  defp maybe_reconstruct_url(struct), do: struct

  defp metrics_hub_url() do
    Config.module_get(Sanbase.SocialData, :metricshub_url)
  end

  defp index_to_source(index) do
    case index do
      "reddit" <> _ -> "reddit"
      "twitter" <> _ -> "twitter"
      "4chan" <> _ -> "4chan"
      "farcaster" <> _ -> "farcaster"
      "telegram" <> _ -> "telegram"
      "bitcointalk" <> _ -> "bitcointalk"
      _ -> nil
    end
  end
end
