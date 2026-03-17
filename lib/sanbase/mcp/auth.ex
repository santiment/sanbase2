defmodule Sanbase.MCP.Auth do
  @doc """
  Resolves the user from the Authorization header.
  Supports both OAuth bearer tokens and API key authentication.
  Tries OAuth first, then falls back to API key.
  """
  alias Boruta.Oauth.Authorization

  @spec headers_list_to_user([{String.t(), String.t()}]) ::
          Sanbase.Accounts.User.t() | nil
  def headers_list_to_user(headers) do
    case get_header(headers, "authorization") do
      {"authorization", header_value} ->
        oauth_to_user(header_value) || apikey_to_user(header_value)

      _ ->
        nil
    end
  end

  def can_execute?(Sanbase.MCP.FetchMetricDataTool, %{metric: _, slug: _}, frame) do
    user = frame.assigns[:current_user]
    not is_nil(user)
  end

  @spec get_header([{String.t(), String.t()}], String.t()) :: {String.t(), String.t()} | nil
  def get_header(headers, name) do
    Enum.find(headers, fn {key, _value} -> key == name end)
  end

  @spec has_authorization_header?([{String.t(), String.t()}]) :: boolean()
  def has_authorization_header?(headers) do
    not is_nil(get_header(headers, "authorization"))
  end

  @spec get_apikey([{String.t(), String.t()}]) :: String.t() | nil
  def get_apikey(headers) do
    case get_header(headers, "authorization") do
      {"authorization", header_value} -> extract_apikey(header_value)
      _ -> nil
    end
  end

  @spec get_auth_method([{String.t(), String.t()}]) :: String.t() | nil
  def get_auth_method(headers) do
    case get_header(headers, "authorization") do
      {"authorization", header_value} -> auth_method_from_header_value(header_value)
      _ -> nil
    end
  end

  defp oauth_to_user(header_value) do
    with "Bearer " <> token <- header_value,
         false <- String.starts_with?(token, "Apikey "),
         {:ok, oauth_token} <- Authorization.AccessToken.authorize(value: token),
         {:ok, user} <- Sanbase.Accounts.User.by_id(Sanbase.Math.to_integer(oauth_token.sub)) do
      user
    else
      _ -> nil
    end
  end

  defp apikey_to_user(header_value) do
    case extract_apikey(header_value) do
      nil ->
        nil

      apikey ->
        case Sanbase.Accounts.Apikey.apikey_to_user(apikey) do
          {:ok, %Sanbase.Accounts.User{} = user} -> user
          {:error, _} -> nil
        end
    end
  end

  defp extract_apikey(header_value) do
    case auth_method_from_header_value(header_value) do
      "apikey" -> extract_apikey_value(header_value)
      _ -> nil
    end
  end

  defp auth_method_from_header_value("Bearer Apikey " <> _), do: "apikey"
  defp auth_method_from_header_value("Apikey " <> _), do: "apikey"

  defp auth_method_from_header_value("Bearer " <> token) do
    cond do
      oauth_token?(token) -> "oauth"
      apikey_token?(token) -> "apikey"
      true -> nil
    end
  end

  defp auth_method_from_header_value(_), do: nil

  defp extract_apikey_value("Bearer Apikey " <> apikey), do: apikey
  defp extract_apikey_value("Apikey " <> apikey), do: apikey
  defp extract_apikey_value("Bearer " <> apikey), do: apikey
  defp extract_apikey_value(_), do: nil

  defp oauth_token?(token) do
    match?({:ok, _}, Authorization.AccessToken.authorize(value: token))
  end

  defp apikey_token?(apikey) do
    match?({:ok, %Sanbase.Accounts.User{}}, Sanbase.Accounts.Apikey.apikey_to_user(apikey))
  end
end
