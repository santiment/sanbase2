defmodule SanbaseWeb.RootController do
  use SanbaseWeb, :controller

  require Logger

  alias Sanbase.Oauth2.Hydra
  alias Sanbase.Auth.User
  alias Sanbase.Pricing.Subscription

  # Used in production mode to serve the reactjs application
  def index(conn, _params) do
    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> Plug.Conn.send_file(200, path("priv/static/index.html"))
  end

  def stripe(conn, _params) do
    {:ok, pi} = Subscription.payment_intent_for_subscription(31, 2)
    render(conn, "stripe.html", %{client_secret: pi.client_secret})
  end

  def webhook(conn, params) do
    IO.inspect(params)
    parse_stripe_resp(params)

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "")
  end

  def parse_stripe_resp(%{
        "data" => %{
          "object" => %{
            "status" => status,
            "metadata" => %{
              "plan_id" => plan_id
            },
            "customer" => customer
          }
        }
      }) do
    IO.inspect(status)
    IO.inspect(plan_id)
    IO.inspect(customer)
  end

  def healthcheck(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "")
  end

  def consent(
        conn,
        %{
          "consent" => consent,
          "token" => token
        } = _params
      ) do
    with {:ok, user} <- bearer_authorize(token),
         {:ok, access_token} <- Hydra.get_access_token(),
         {:ok, redirect_url, client_id} <- Hydra.get_consent_data(consent, access_token),
         :ok <- Hydra.manage_consent(consent, access_token, user, client_id) do
      redirect(conn, external: redirect_url)
    else
      _ -> redirect(conn, to: "/")
    end
  end

  defp path(file) do
    Application.app_dir(:sanbase)
    |> Path.join(file)
  end

  defp bearer_authorize(token) do
    with {:ok, %User{salt: salt} = user, %{"salt" => salt}} <-
           SanbaseWeb.Guardian.resource_from_token(token) do
      {:ok, user}
    else
      _ ->
        Logger.warn("Invalid bearer token in request: #{token}")
        {:error, :invalid_token}
    end
  end
end
