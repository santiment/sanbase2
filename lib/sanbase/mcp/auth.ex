defmodule Sanbase.MCP.Auth do
  @doc ~s"""
  Returns the user which corresponds to the given API key in the
  authorization header, if present
  """
  @spec headers_list_to_user([{String.t(), String.t()}]) ::
          Sanbase.Accounts.User.t() | nil
  def headers_list_to_user(headers) do
    case get_header(headers, "authorization") do
      {"authorization", header_value} ->
        apikey = extract_apikey(header_value)

        case Sanbase.Accounts.Apikey.apikey_to_user(apikey) do
          {:ok, %Sanbase.Accounts.User{} = user} ->
            user

          {:error, _} ->
            nil
        end

      _ ->
        nil
    end
  end

  def can_execute?(Sanbase.MCP.FetchMetricDataTool, %{metric: _, slug: _}, frame) do
    # TODO: Check user subscription plan to decide if the user has access
    # to the metric. The slug is probably not needed for this check
    user = frame.assigns[:current_user]
    not is_nil(user)
  end

  @spec headers_list_to_user([{String.t(), String.t()}]) ::
          String.t() | nil
  def get_apikey(headers) do
    case get_header(headers, "authorization") do
      {"authorization", header_value} ->
        extract_apikey(header_value)

      _ ->
        nil
    end
  end

  @spec headers_list_to_user([{String.t(), String.t()}]) ::
          {String.t(), String.t()} | nil
  def get_header(headers, name) do
    Enum.find(headers, fn {key, _value} -> key == name end)
  end

  # Private functions
  defp extract_apikey(header_value) do
    case header_value do
      # If you put just `Apikey apikey` as value in MCP Inspector, it automatically
      # prepends it with Bearer. Some MCP clients might not do that. Just to cover
      # more cases, we extract the apikey from multiple different formats
      "Bearer Apikey " <> apikey -> apikey
      "Apikey " <> apikey -> apikey
      "Bearer " <> apikey -> apikey
      _ -> nil
    end
  end
end
