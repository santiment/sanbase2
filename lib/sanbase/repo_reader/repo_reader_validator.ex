defmodule Sanbase.RepoReader.Validator do
  @moduledoc false
  require Logger

  @external_resource json_file = Path.join([__DIR__, "jsonschema.json"])
  @jsonschema json_file
              |> File.read!()
              |> Jason.decode!()
              |> ExJsonSchema.Schema.resolve()

  @custom_validations ["social", "contracts", "general[ticker]", "general[name]"]

  def schema, do: @jsonschema

  @doc ~s"""
  Validate that the provided Elixir map conforms to the jsonschema and the custom
  validations. The jsonschema checks for required fields, types and some basic value
  restrictions (min, max, length). The custom validations check that a string is valid
  URL or that the blockchain is in the list of available blockchains.
  """
  def validate(%{} = projects_map) do
    Enum.reduce_while(projects_map, :ok, fn {slug, data}, _acc ->
      with :ok <- jsonschema_validate(data),
           :ok <- custom_validate(data) do
        {:cont, :ok}
      else
        {:error, error} ->
          {:halt, {:error, "Error in file with slug #{slug}: #{inspect(error)}"}}
      end
    end)
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

  defp custom_validate("social", %{"social" => %{} = social}) do
    Enum.reduce_while(social, :ok, fn {media, link}, _acc ->
      case validate_url(link, media) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, "Invalid social link: #{error}"}}
      end
    end)
  end

  defp custom_validate("contracts", %{"blockchain" => %{"contracts" => contracts}}) do
    Enum.reduce_while(contracts, :ok, fn contract_map, _acc ->
      case validate_contract_map(contract_map) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, "Invalid contract map: #{error}"}}
      end
    end)
  end

  defp custom_validate("general[name]", %{"general" => %{"name" => name}}) do
    cond do
      not is_binary(name) or String.length(name) < 2 ->
        {:error, "The name must be a string of length 2 or more"}

      String.at(name, 0) != name |> String.at(0) |> String.upcase() ->
        {:error, "The name must start with a capital letter or a number"}

      not ((String.at(name, 0) >= "A" and String.at(name, 0) <= "Z") or
               (String.at(name, 0) >= "0" and String.at(name, 0) <= "9")) ->
        {:error, "The name must start with a capital letter or a number"}

      true ->
        :ok
    end
  end

  defp custom_validate("general[ticker]", %{"general" => %{"ticker" => ticker}}) do
    cond do
      not String.match?(ticker, ~r/^[[:alnum:]]+$/) ->
        {:error, "The ticker must contain only alphanumeric characters"}

      String.upcase(ticker) != ticker ->
        {:error, "All letters in the ticker must be uppercased"}

      true ->
        :ok
    end
  end

  defp custom_validate("general[ecosystem]", %{"general" => %{"ecosystem" => ecosystem}}) do
    if Sanbase.AvailableSlugs.valid_slug?(ecosystem) do
      :ok
    else
      {:error, "The ecosystem must be an existing slug"}
    end
  end

  defp custom_validate(_, _), do: :ok

  defp validate_url(url, type) do
    uri = URI.parse(url)

    if uri.scheme != nil and is_binary(uri.host) and uri.host =~ "." do
      :ok
    else
      {:error, "The #{type} URL #{url} is invalid - it has missing schema or host"}
    end
  end

  defp validate_contract_map(map) do
    if map["blockchain"] in Sanbase.BlockchainAddress.available_blockchains() do
      :ok
    else
      {:error, "Blockchain #{map["blockchain"]} is missing or unsupported"}
    end
  end
end
