defmodule SanbaseWeb.Graphql.Middlewares.RefreshTokenAgeCheck do
  @moduledoc """
  Authenticate that the request contains a valid JWT refresh token that was
  issued in a specific time interval. In most cases the check will be that the
  token is issued no more than X minutes ago.

  Example:

      query do
        field :destroy_all_sessions, :boolean do
          middleware RefreshTokenAgeCheck, less_than: "10m"
          resolve &AuthResolver.destroy_all_sessions/3
        end
      end
  """
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution

  @doc ~s"""
  Decides whether the user has access or not.

  The user must have authenticated less than the `:less_than` interval ago,
  specified in the opts. This way we can enforce authentication to some resources
  only after the user authenticates.
  """

  def call(%Resolution{context: %{jwt_tokens: %{refresh_token: refresh_token}}} = resolution, opts) do
    age_less_than = Keyword.fetch!(opts, :less_than)

    case SanbaseWeb.Guardian.decode_and_verify(refresh_token) do
      {:ok, %{"iat" => issued_at_unix}} ->
        seconds = Sanbase.DateTimeUtils.str_to_sec(age_less_than)
        unix_now = DateTime.to_unix(DateTime.utc_now())

        if unix_now - issued_at_unix < seconds do
          resolution
        else
          Resolution.put_result(resolution, {:error, error_msg(age_less_than)})
        end

      _ ->
        Resolution.put_result(resolution, {:error, :unauthorized})
    end
  end

  def call(resolution, _opts), do: Resolution.put_result(resolution, {:error, :unauthorized})

  defp error_msg(less_than) do
    less_than_human_readable = Sanbase.DateTimeUtils.interval_to_str(less_than)

    """
    Unauthorized. Reason: The authentication must have been done less than \
    #{less_than_human_readable} ago. Repeat the authentication process and try \
    again.
    """
  end
end
