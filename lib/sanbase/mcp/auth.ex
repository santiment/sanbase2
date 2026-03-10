defmodule Sanbase.MCP.Auth do
  @doc """
  Resolves the user from the OAuth bearer token in the Authorization header.
  Uses boruta's JWT token validation.
  """
  alias Boruta.Oauth.Authorization

  @spec headers_list_to_user([{String.t(), String.t()}]) ::
          Sanbase.Accounts.User.t() | nil
  def headers_list_to_user(headers) do
    case extract_bearer_token(headers) do
      nil ->
        nil

      bearer ->
        case Authorization.AccessToken.authorize(value: bearer) do
          {:ok, token} ->
            case Sanbase.Accounts.User.by_id(Sanbase.Math.to_integer(token.sub)) do
              {:ok, user} -> user
              _ -> nil
            end

          _ ->
            nil
        end
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

  defp extract_bearer_token(headers) do
    case get_header(headers, "authorization") do
      {"authorization", value} ->
        case String.split(value, " ", parts: 2) do
          [scheme, token] when byte_size(token) > 0 ->
            if String.downcase(scheme) == "bearer", do: token, else: nil

          _ ->
            nil
        end

      _ ->
        nil
    end
  end
end
