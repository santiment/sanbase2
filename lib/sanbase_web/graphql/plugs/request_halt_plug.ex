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

  def halt_sansheets_request?(conn, %{auth: %{plan: plan_name} = auth}) do
    case sansheets_request?(conn) and plan_name == "FREE" do
      true ->
        user_id = get_in(auth, [:current_user, Access.key(:id)])

        Logger.info(
          "[RequestHaltPlug] Halt sansheets request with FREE plan. User id: #{user_id}"
        )

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
        requested_product: "SANAPI",
        auth: %{current_user: user, auth_method: auth_method, plan: plan_name}
      }) do
    case ApiCallLimit.get_quota(:user, user, auth_method) do
      {:error, %{reason: :rate_limited, blocked_for_seconds: _} = rate_limit_map} ->
        conn =
          Sanbase.Utils.Conn.put_extra_resp_headers(
            conn,
            rate_limit_headers(rate_limit_map)
          )

        Logger.info("[RequestHaltPlug] Rate limited user id #{user.id}")

        {true, conn, get_quota_error_to_error_map(rate_limit_map, user, plan_name)}

      {:error, %{reason: :response_size_limit_exceeded, blocked_for_seconds: _} = rate_limit_map} ->
        Logger.info("[RequestHaltPlug] Response size limit exceeded for user id #{user.id}")

        {true, conn, get_quota_error_to_error_map(rate_limit_map, user, plan_name)}

      {:ok, %{quota: :infinity}} ->
        {false, put_private(conn, :has_api_call_limit_quota_infinity, true)}

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
          requested_product: "SANAPI",
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

        Logger.info("[RequestHaltPlug] Rate limit remote ip #{remote_ip}}")

        {true, conn, get_quota_error_to_error_map(rate_limit_map, _user = nil, _plan = "FREE")}

      {:ok, %{quota: :infinity}} ->
        {false, put_private(conn, :has_api_call_limit_quota_infinity, true)}

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

  defp sansheets_request?(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [user_agent] -> String.contains?(user_agent, "Google-Apps-Script")
      _ -> false
    end
  end

  defp get_quota_error_to_error_map(
         %{reason: :rate_limited} = rate_limit_map,
         user_or_nil,
         plan_name
       ) do
    %{
      error_msg: rate_limit_error_message(rate_limit_map, user_or_nil, plan_name),
      error_code: 429
    }
  end

  defp get_quota_error_to_error_map(
         %{reason: :response_size_limit_exceeded} = rate_limit_map,
         user_or_nil,
         plan_name
       ) do
    %{
      error_msg:
        response_size_limit_exceeded_error_message(rate_limit_map, user_or_nil, plan_name),
      error_code: 429
    }
  end

  defp rate_limit_error_message(%{blocked_for_seconds: seconds}, user, plan_name) do
    human_duration = Sanbase.DateTimeUtils.seconds_to_human_readable(seconds)

    message_details =
      case user do
        nil ->
          """
          The request is made without user authentication. If this is not expected, check the authorization logic of your code.
          """

        %Sanbase.Accounts.User{} ->
          """
          The request is made by user with id #{user.id} using plan #{plan_name}
          You can update your subscription plan or you can contact Santiment Support if you
          made a mistake and exhausted your API calls and you want Santiment to reset your limits.

          You can also reset the limits yourself once every 90 days by visiting your user profile on
          #{Path.join(SanbaseWeb.Endpoint.website_url(), "/account")} and resetting your API usage.
          """
      end

    """
    API Rate Limit Reached. Try again in #{seconds} seconds (#{human_duration}).
    #{message_details}
    """
  end

  defp response_size_limit_exceeded_error_message(
         %{blocked_for_seconds: seconds},
         user,
         plan_name
       ) do
    human_duration = Sanbase.DateTimeUtils.seconds_to_human_readable(seconds)

    message_details =
      case user do
        nil ->
          """
          The request is made without user authentication. If this is not expected, check the authorization logic of your code.
          """

        %Sanbase.Accounts.User{} ->
          """
          The request is made by user with id #{user.id} using plan #{plan_name}
          You can update your subscription plan or you can contact Santiment Support if you
          made a mistake and exhausted your limits and you want Santiment to reset your limits.

          You can also reset the limits yourself once every 90 days by visiting your user profile on
          #{Path.join(SanbaseWeb.Endpoint.website_url(), "/account")} and resetting your API usage.
          """
      end

    """
    Total response size (in MBs) limit exceeded. Try again in #{seconds} seconds (#{human_duration}).
    #{message_details}
    """
  end
end
