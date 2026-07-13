defmodule SanbaseWeb.Plug.AdminEmailAuthPlug do
  @moduledoc ~s"""
  """

  @behaviour Plug
  import Plug.Conn

  alias Sanbase.Accounts
  alias Sanbase.Accounts.User

  # Captured at compile time. `Mix` is not available at runtime in releases, so
  # this can never be :dev/:test in a production build. This prevents the
  # passwordless dev login from being enabled by a missing/incorrect
  # DEPLOYMENT_ENVIRONMENT runtime variable in production.
  @compile_env Mix.env()

  def init(opts), do: opts

  def call(%{params: %{"email" => email} = params} = conn, _) do
    if passwordless_dev_login_allowed?() do
      login(conn, email)
    else
      case params["token"] do
        nil ->
          conn
          |> send_resp(
            400,
            "Bad Request -- User Token Missing. Params present: #{Map.keys(params) |> Enum.join(", ")}"
          )
          |> halt()

        token ->
          check_and_login(conn, email, token)
      end
    end
  end

  # The compile-time env alone decides, same as the login gate in
  # SanbaseWeb.AdminAuthenticateLive. Deployed envs run releases compiled with
  # MIX_ENV=prod, so the token flow is always enforced there. Checking the
  # runtime deployment_env here would only break local login when
  # DEPLOYMENT_ENVIRONMENT is set to a non-dev value (e.g. when testing
  # stage-only features locally).
  defp passwordless_dev_login_allowed?() do
    @compile_env in [:dev, :test]
  end

  defp check_and_login(conn, email, token) do
    device_data = SanbaseWeb.Guardian.device_data(conn)

    with {:ok, user} <- User.find_or_insert_by(:email, email),
         true <- User.Email.email_token_valid?(user, token),
         {:ok, jwt_tokens_map} <- SanbaseWeb.Guardian.get_jwt_tokens(user, device_data),
         {:ok, user} <- User.Email.mark_email_token_as_validated(user),
         {:ok, _, _user} <- Accounts.forward_registration(user, "email_login_verify", %{}) do
      tokens = Map.take(jwt_tokens_map, [:access_token, :refresh_token])

      conn
      |> SanbaseWeb.Guardian.add_jwt_tokens_to_conn_session(tokens)
    else
      _ ->
        conn |> send_resp(403, "Failed to login") |> halt()
    end
  end

  defp login(conn, email) do
    device_data = SanbaseWeb.Guardian.device_data(conn)

    with {:ok, user} <- User.find_or_insert_by(:email, email),
         {:ok, jwt_tokens_map} <- SanbaseWeb.Guardian.get_jwt_tokens(user, device_data) do
      SanbaseWeb.Guardian.add_jwt_tokens_to_conn_session(
        conn,
        Map.take(jwt_tokens_map, [:access_token, :refresh_token])
      )
    else
      _ ->
        conn |> send_resp(403, "Failed to login") |> halt()
    end
  end
end
