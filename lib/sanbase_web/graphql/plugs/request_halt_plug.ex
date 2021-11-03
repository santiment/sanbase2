defmodule SanbaseWeb.Graphql.RequestHaltPlug do
  @moduledoc ~s"""
  Plug that halts requests if some conditions are met

  It performs the following checks:
  - Check if the request comes from SanSheets and if the user
  has access to it
  - Check if the rate limits are exceeded
  """

  @behaviour Plug

  @compile {:inline,
            should_halt?: 3,
            halt_sansheets_request?: 2,
            halt_api_call_limit_reached?: 2,
            build_error_msg: 1}

  import Plug.Conn

  alias Sanbase.ApiCallLimit
  alias SanbaseWeb.Graphql.RequestHaltPlug

  require Logger

  @product_id_api Sanbase.Billing.Product.product_api()

  @should_halt_methods [
    &RequestHaltPlug.halt_sansheets_request?/2,
    &RequestHaltPlug.halt_api_call_limit_reached?/2
  ]

  def init(opts), do: opts

  def call(conn, _) do
    context = conn.private[:absinthe][:context]

    case should_halt?(conn, context, @should_halt_methods) do
      {false, conn} ->
        conn

      {true, conn, error_map} ->
        %{error_msg: error_msg, error_code: error_code} = error_map

        conn
        |> put_resp_content_type("application/json", "charset=utf-8")
        |> send_resp(error_code, build_error_msg(error_msg))
        |> halt()
    end
  end

  defp should_halt?(conn, _context, []), do: {false, conn}

  defp should_halt?(conn, context, [halt_method | rest]) do
    case halt_method.(conn, context) do
      {false, conn} -> should_halt?(conn, context, rest)
      {true, conn, error_map} -> {true, conn, error_map}
    end
  end

  def halt_sansheets_request?(conn, %{auth: %{subscription: %{plan: %{name: plan_name}}}}) do
    case is_sansheets_request(conn) and plan_name == "FREE" do
      true ->
        error_map = %{
          error_msg: """
          You need to upgrade Sanbase Pro in order to use SanSheets.
          If you already have Sanbase Pro, please make sure that a correct API key is provided.
          """,
          error_code: 401
        }

        {true, conn, error_map}

      false ->
        {false, conn}
    end
  end

  def halt_sansheets_request?(conn, _context), do: {false, conn}

  def halt_api_call_limit_reached?(conn, %{
        rate_limiting_enabled: true,
        product_id: @product_id_api,
        auth: %{current_user: user, auth_method: auth_method}
      }) do
    case ApiCallLimit.get_quota(:user, user, auth_method) do
      {:error, %{blocked_for_seconds: _} = rate_limit_map} ->
        conn =
          Sanbase.Utils.Conn.put_extra_resp_headers(
            conn,
            rate_limit_headers(rate_limit_map)
          )

        {true, conn, rate_limit_map_to_error_map(rate_limit_map)}

      {:ok, %{quota: :infinity}} ->
        {false, conn}

      {:ok, %{quota: _} = quota_map} ->
        conn =
          Sanbase.Utils.Conn.put_extra_resp_headers(
            conn,
            rate_limit_headers(quota_map)
          )

        {false, conn}
    end
  end

  def halt_api_call_limit_reached?(
        conn,
        %{
          rate_limiting_enabled: true,
          product_id: @product_id_api,
          remote_ip: remote_ip
        } = context
      ) do
    remote_ip = Sanbase.Utils.IP.ip_tuple_to_string(remote_ip)
    auth_method = context[:auth][:auth_method] || :unauthorized

    case ApiCallLimit.get_quota(:remote_ip, remote_ip, auth_method) do
      {:error, %{blocked_for_seconds: _} = rate_limit_map} ->
        conn =
          Sanbase.Utils.Conn.put_extra_resp_headers(
            conn,
            rate_limit_headers(rate_limit_map)
          )

        {true, conn, rate_limit_map_to_error_map(rate_limit_map)}

      {:ok, %{quota: :infinity}} ->
        {false, conn}

      {:ok, %{quota: _} = quota_map} ->
        conn =
          Sanbase.Utils.Conn.put_extra_resp_headers(
            conn,
            rate_limit_headers(quota_map)
          )

        {false, conn}
    end
  end

  def halt_api_call_limit_reached?(conn, _context), do: {false, conn}

  defp rate_limit_error_message(%{blocked_for_seconds: seconds}) do
    human_duration = Sanbase.DateTimeUtils.seconds_to_human_readable(seconds)

    """
    API Rate Limit Reached. Try again in #{seconds} seconds (#{human_duration})
    """
  end

  defp rate_limit_headers(map) do
    %{
      api_calls_limits: api_calls_limit,
      api_calls_remaining: api_calls_remaining
    } = map

    headers = [
      {"x-ratelimit-remaining-month", api_calls_remaining.month},
      {"x-ratelimit-remaining-hour", api_calls_remaining.hour},
      {"x-ratelimit-remaining-minute", api_calls_remaining.minute},
      {"x-ratelimit-remaining", api_calls_remaining.minute},
      {"x-ratelimit-limit-month", api_calls_limit.month},
      {"x-ratelimit-limit-hour", api_calls_limit.hour},
      {"x-ratelimit-limit-minute", api_calls_limit.minute},
      {"x-ratelimit-limit", api_calls_limit.minute}
    ]

    case Map.get(map, :blocked_for_seconds) do
      nil ->
        headers

      blocked_for_seconds ->
        [{"x-ratelimit-reset", blocked_for_seconds} | headers]
    end
  end

  defp build_error_msg(msg) do
    %{errors: %{details: msg}} |> Jason.encode!()
  end

  defguard no_auth_header(header) when header in [[], ["null"], [""], nil]

  defp is_sansheets_request(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [user_agent] -> String.contains?(user_agent, "Google-Apps-Script")
      _ -> false
    end
  end

  defp rate_limit_map_to_error_map(rate_limit_map) do
    %{
      error_msg: rate_limit_error_message(rate_limit_map),
      error_code: 429
    }
  end
end
