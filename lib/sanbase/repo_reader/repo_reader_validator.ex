defmodule Sanbase.RepoReader.Validator do
  require Logger

  @external_resource json_file = Path.join([__DIR__, "jsonschema.json"])
  @jsonschema File.read!(json_file) |> Jason.decode!() |> ExJsonSchema.Schema.resolve()

  @social_channels ["discord", "twitter", "slack", "telegram", "reddit", "bitcointalk", "blog"]
  @custom_validations ["twitter", "discord", "slack", "contracts"]

  def schema(), do: @jsonschema

  @doc ~s"""
  Validate that the provided Elixir map conforms to the jsonschema and the custom
  validations. The jsonschema checks for required fields, types and some basic value
  restrictions (min, max, length). The custom validations check that a string is valid
  URL or that the blockchain is in the list of available blockchains.
  """
  def validate(%{} = map) do
    with :ok <- jsonschema_validate(map),
         :ok <- custom_validate(map) do
      :ok
    end
  end

  # Private functions

  defp jsonschema_validate(map) do
    ExJsonSchema.Validator.validate(@jsonschema, map)
  end

  defp custom_validate(map) do
    Enum.reduce_while(@custom_validations, :ok, fn key, _acc ->
      case custom_validate(key, map) do
        :ok -> {:cont, :ok}
        {:error, _} = error_tuple -> {:halt, error_tuple}
      end
    end)
  end

  defp custom_validate(media, %{"social" => %{} = social})
       when media in @social_channels and
              is_map_key(social, media) do
    validate_url(_link = social[media], media)
  end

  defp custom_validate("contracts", %{"blockchain" => %{"contracts" => contracts}}) do
    Enum.reduce_while(contracts, :ok, fn contract_map, _acc ->
      case validate_contract_map(contract_map) do
        :ok -> :ok
        {:error, error} -> {:error, "Invalid contract map: #{error}"}
      end
    end)
  end

  defp custom_validate(_, _), do: :ok

  defp validate_url(url, type) do
    uri = URI.parse(url)

    case uri.scheme != nil and uri.host =~ "." do
      true -> :ok
      false -> {:error, "The #{type} URL #{url} is invalid - it has missing schema or host"}
    end
  end

  defp validate_contract_map(map) do
    case map["blockchain"] in Sanbase.BlockchainAddress.available_blockchains() do
      true -> :ok
      false -> {:error, "Blockchain #{map["blockchain"]} is missing or unsupported"}
    end
  end
end
