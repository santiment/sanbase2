defmodule Sanbase.MCP.Knowledge.GetUserAccountTool do
  @moduledoc """
  Look up one Sanbase account to resolve a support request: who the user is, their
  subscriptions (current and past), their API call limits and usage, recent invoices and
  restrictions such as an MCP ban.

  Pass a user id, an email (matched case-insensitively) or a username.

  Reading the result:
  - `as_of` is when the lookup was made. The API call counts and `blocked` in `api_limits`
    are valid at that instant, in the windows starting at its `period_starts`; they change
    by the minute. The other sections are read right after it.
  - `subscriptions`: newest first. `status` is Stripe's: `active`, `trialing`, `past_due`
    (a renewal payment failed and Stripe is retrying), `unpaid`, `canceled`, `incomplete`
    (first payment not completed) or `incomplete_expired` (it never was). An `active` one
    with `cancel_at_period_end: true` was cancelled by the user and ends at
    `current_period_end`. A current subscription (`active`, `trialing`, `past_due`) also has
    the `api_call_limits` its plan gives. Limits are never summed: the rate limiter uses
    the current SanAPI subscription if there is one, else the current Sanbase one, else the
    free plan. The limits in force are in `api_limits`.
  - `api_limits` is what the rate limiter enforces, over calendar month/hour/minute in UTC,
    for API key and Sanbase (JWT) calls together: the limits, the calls made and remaining,
    and `blocked` when the user is rate limited right now. The calls made can trail the
    real ones, as each API node saves them in batches of up to ~200 calls.
  - Every section is fetched separately: one that fails has an `error` and the rest are
    still returned.

  The result holds personal data. Use it to help this user only, and never paste it into
  FAQ drafts.
  """

  use Anubis.Server.Component, type: :tool

  import Ecto.Query

  require Logger

  alias Anubis.Server.Response
  alias Sanbase.Accounts.User
  alias Sanbase.Accounts.UserApikeyToken
  alias Sanbase.Billing.InvoiceMirror
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.PromoTrial
  alias Sanbase.MCP.Knowledge.Format
  alias Sanbase.MCP.ToolError
  alias Sanbase.Repo

  @invoices_limit 10
  # `users.id` is a bigint: a larger number cannot be an id, and Postgrex raises on it.
  @max_user_id 9_223_372_036_854_775_807
  @current_statuses [:active, :past_due, :trialing]

  def name(), do: "get_user_account"

  @impl true
  def annotations() do
    %{
      "title" => "Get User Account",
      "readOnlyHint" => true,
      "destructiveHint" => false,
      "openWorldHint" => false
    }
  end

  schema do
    field(:user, {:either, {:string, :integer}},
      required: true,
      description: "The user's id, email or username."
    )
  end

  @impl true
  def execute(%{user: term}, frame) do
    case find_user(term) do
      {:ok, user} ->
        Logger.info(
          "[MCP Knowledge] User #{frame.assigns.current_user.id} looked up account #{user.id}"
        )

        {:reply, Response.json(Response.tool(), account(user)), frame}

      {:error, message} ->
        {:reply, Format.error_response(ToolError.permanent(message)), frame}
    end
  end

  # Numeric -> id, contains `@` -> email, otherwise -> username. A username can be all
  # digits or contain `@`, so the first two fall back to it.
  defp find_user(term) do
    term = term |> to_string() |> String.trim()

    result =
      cond do
        term == "" -> {:error, "Pass a user id, email or username."}
        Regex.match?(~r/^\d+$/, term) -> by_id(String.to_integer(term))
        String.contains?(term, "@") -> by_email(term)
        true -> {:error, :not_found}
      end

    with {:error, :not_found} <- result do
      case User.by_username(term) do
        {:ok, %User{} = user} -> {:ok, user}
        {:error, _} -> {:error, "No user found for #{inspect(term)}."}
      end
    end
  end

  defp by_id(id) when id <= @max_user_id do
    case User.by_id(id) do
      {:ok, %User{} = user} -> {:ok, user}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp by_id(_id), do: {:error, :not_found}

  # Users type their email with any casing, so an exact match is only preferred.
  defp by_email(email) do
    with {:error, _} <- User.by_email(email) do
      from(u in User, where: fragment("lower(?)", u.email) == ^String.downcase(email))
      |> Repo.all()
      |> case do
        [user] ->
          {:ok, user}

        [] ->
          {:error, :not_found}

        users ->
          {:error,
           "Several users have the email #{inspect(email)} in different casing, ids " <>
             "#{users |> Enum.map(& &1.id) |> Enum.join(", ")}. Look up one of them by id."}
      end
    end
  end

  defp account(%User{} = user) do
    user = Repo.preload(user, [:eth_accounts])
    as_of = DateTime.utc_now()

    %{
      as_of: as_of,
      user: section(:user, fn -> user_info(user) end),
      subscriptions: section(:subscriptions, fn -> subscriptions(user) end),
      promo_trials: section(:promo_trials, fn -> promo_trials(user) end),
      api_limits: section(:api_limits, fn -> api_limits(user, as_of) end),
      invoices: section(:invoices, fn -> invoices(user) end),
      admin_links: admin_links(user)
    }
  end

  # One failing source (e.g. a bundle that never synced) must not hide the rest.
  defp section(name, fun) do
    fun.()
  rescue
    error ->
      Logger.error(
        "[MCP Knowledge] get_user_account #{name} failed: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      %{error: "Could not load #{name}: #{Exception.message(error)}"}
  end

  defp user_info(%User{} = user) do
    %{
      id: user.id,
      username: user.username,
      email: user.email,
      name: user.name,
      registered_at: user.inserted_at,
      is_registered: user.is_registered,
      is_team_member: Sanbase.MCP.ToolInvocation.team_member?(user),
      is_superuser: user.is_superuser,
      stripe_customer_id: user.stripe_customer_id,
      san_balance: user.san_balance,
      login_methods: login_methods(user),
      metric_access_level: user.metric_access_level,
      feature_access_level: user.feature_access_level,
      api_keys_count: api_keys_count(user),
      mcp_ban:
        if(user.is_mcp_banned,
          do: %{banned_at: user.mcp_banned_at, reason: user.mcp_banned_reason}
        )
    }
  end

  defp login_methods(%User{} = user) do
    [
      user.email && "email",
      user.eth_accounts != [] && "ethereum wallet",
      user.twitter_id && "twitter"
    ]
    |> Enum.filter(&is_binary/1)
  end

  defp api_keys_count(%User{id: user_id}) do
    from(t in UserApikeyToken, where: t.user_id == ^user_id) |> Repo.aggregate(:count)
  end

  defp subscriptions(%User{id: user_id}) do
    from(s in Subscription,
      where: s.user_id == ^user_id,
      order_by: [desc: s.inserted_at],
      preload: [plan: :product]
    )
    |> Repo.all()
    |> Enum.map(&subscription_row/1)
  end

  defp subscription_row(%Subscription{} = s) do
    %{
      id: s.id,
      product: s.plan && s.plan.product && s.plan.product.name,
      plan: s.plan && s.plan.name,
      billing_interval: s.plan && s.plan.interval,
      status: s.status,
      payment_type: s.type,
      cancel_at_period_end: s.cancel_at_period_end,
      current_period_end: s.current_period_end,
      trial_end: s.trial_end,
      created_at: s.inserted_at,
      updated_at: s.updated_at,
      stripe_subscription_id: s.stripe_id,
      grant: grant(Subscription.grant(s))
    }
    |> Map.merge(rate_limits(s))
  end

  defp rate_limits(%Subscription{status: status} = s) when status in @current_statuses do
    %{api_call_limits: Sanbase.ApiCallLimit.subscription_api_call_limits(s)}
  end

  defp rate_limits(_subscription), do: %{}

  defp grant(nil), do: nil

  defp grant(grant) do
    %{
      extra_api_calls_per_month: grant.extra_api_calls_per_month,
      full_history_packages: grant.full_history_packages,
      full_history_metrics: grant.full_history_metrics,
      note: grant.note,
      granted_at: grant.granted_at
    }
  end

  defp promo_trials(%User{id: user_id}) do
    from(pt in PromoTrial, where: pt.user_id == ^user_id, order_by: [desc: pt.inserted_at])
    |> Repo.all()
    |> Enum.map(fn pt ->
      %{trial_days: pt.trial_days, plans: pt.plans, created_at: pt.inserted_at}
    end)
  end

  defp api_limits(%User{} = user, as_of) do
    case Sanbase.ApiCallLimit.status(:user, user, as_of) do
      {:ok, status} ->
        status

      {:error, :not_found} ->
        %{
          as_of: as_of,
          message: "No API call limit record: the user has never made an authenticated call."
        }
    end
  end

  defp invoices(%User{id: user_id}) do
    list =
      from(i in InvoiceMirror.Invoice,
        where: i.user_id == ^user_id,
        order_by: [desc: i.invoiced_at],
        limit: @invoices_limit
      )
      |> Repo.all()
      |> Enum.map(fn i ->
        %{
          invoice_number: i.invoice_number,
          status: i.status,
          billing_reason: i.billing_reason,
          total: format_amount(i.total, i.currency),
          amount_paid: format_amount(i.amount_paid, i.currency),
          paid_from_credit: format_amount(i.credit_applied, i.currency),
          invoiced_at: i.invoiced_at,
          paid_at: i.paid_at
        }
      end)

    %{mirror_synced_at: InvoiceMirror.last_synced_at(), latest: list}
  end

  # Stripe amounts are in cents.
  defp format_amount(cents, currency) when is_integer(cents) do
    amount = :erlang.float_to_binary(cents / 100, decimals: 2)
    String.trim("#{amount} #{currency && String.upcase(currency)}")
  end

  defp format_amount(_cents, _currency), do: nil

  defp admin_links(%User{id: id}) do
    admin_url = SanbaseWeb.Endpoint.admin_url()

    %{
      overview: "#{admin_url}/admin/user_overview?user_id=#{id}",
      user: "#{admin_url}/admin/generic/#{id}?resource=users"
    }
  end
end
