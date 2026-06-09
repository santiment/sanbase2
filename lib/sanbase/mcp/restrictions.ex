defmodule Sanbase.MCP.Restrictions do
  @moduledoc """
  Plan-aware rate limits for the Santiment MCP server.

  Three tiers gate every authenticated user's MCP usage:

    * `:free` — Sanbase FREE (no subscription) and SanAPI FREE
    * `:pro`  — Sanbase PRO
    * `:max`  — Sanbase MAX (incl. legacy PRO_PLUS / BUSINESS_* / CUSTOM*)
                and every paid SanAPI plan (PRO, BUSINESS_PRO, BUSINESS_MAX,
                CUSTOM, CUSTOM_*).

  When a user has subscriptions across both products, the highest tier wins.

  Windows are rolling: `minute` = last 60s, `hour` = last 3600s, `day` =
  last 86_400s, `month` = last 30 days. The month bucket is rolling so it
  does not reset on calendar month boundaries — same shape across all four
  windows.

  ## Limits

  Global (all MCP tools combined):

      +-------+--------+------+-------+--------+
      | Tier  | Minute | Hour | Day   | Month  |
      +-------+--------+------+-------+--------+
      | free  |     15 |   30 |    50 |     50 |
      | pro   |     30 |  250 |   600 |  2,000 |
      | max   |     60 |  600 | 2,000 | 10,000 |
      +-------+--------+------+-------+--------+

  Per-tool sub-cap for `combined_trends_tool` (the only LLM-using tool —
  costlier to serve, so it has a tighter envelope inside the global budget):

      +-------+--------+------+-----+-------+
      | Tier  | Minute | Hour | Day | Month |
      +-------+--------+------+-----+-------+
      | free  |      2 |    5 |  10 |    10 |
      | pro   |      5 |   40 | 150 |   300 |
      | max   |     10 |   80 | 400 |   800 |
      +-------+--------+------+-----+-------+

  ## Tier mapping

      +---------+------------------------------------+-------+
      | Product | Plan name                          | Tier  |
      +---------+------------------------------------+-------+
      | SANBASE | FREE                               | free  |
      | SANBASE | PRO                                | pro   |
      | SANBASE | PRO_PLUS, MAX, BUSINESS_PRO,       | max   |
      |         | BUSINESS_MAX, CUSTOM, CUSTOM_*,    |       |
      |         | PREMIUM                            |       |
      | SANAPI  | FREE                               | free  |
      | SANAPI  | BASIC, PRO, BUSINESS_PRO,          | max   |
      |         | BUSINESS_MAX, CUSTOM, CUSTOM_*,    |       |
      |         | PREMIUM                            |       |
      +---------+------------------------------------+-------+

  Unauthenticated users are blocked at the server layer before reaching
  this module. Team members (`@santiment.net` + configured `team_emails`)
  bypass rate-limit checks entirely.

  ## Overriding in tests

  Application env deep-merges into the defaults — set only what you need:

      Application.put_env(:sanbase, Sanbase.MCP.Restrictions,
        global: %{free: %{minute: 3}}
      )
  """

  alias Sanbase.Accounts.User
  alias Sanbase.Billing.{Plan, Product, Subscription}

  # FIXME: do not apply the big free-plan restrictions yet — keeping the
  # tighter target values commented so we can switch back easily.
  @global %{
    # free: %{minute: 15, hour: 30, day: 50, month: 50},
    free: %{minute: 25, hour: 100, day: 500, month: 2_000},
    pro: %{minute: 30, hour: 250, day: 600, month: 2_000},
    max: %{minute: 60, hour: 600, day: 2_000, month: 10_000}
  }

  # FIXME: do not apply the big free-plan restrictions yet — keeping the
  # tighter target values commented so we can switch back easily.
  @combined_trends %{
    # free: %{minute: 2, hour: 5, day: 10, month: 10},
    free: %{minute: 3, hour: 20, day: 50, month: 100},
    pro: %{minute: 5, hour: 40, day: 150, month: 300},
    max: %{minute: 10, hour: 80, day: 400, month: 800}
  }

  @tiers [:free, :pro, :max]

  def tiers, do: @tiers

  def global_limits(tier) when tier in @tiers, do: merge_overrides(:global, tier, @global[tier])

  def combined_trends_limits(tier) when tier in @tiers,
    do: merge_overrides(:combined_trends, tier, @combined_trends[tier])

  defp merge_overrides(group, tier, defaults) do
    overrides =
      :sanbase
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(group, %{})
      |> Map.get(tier, %{})

    Map.merge(defaults, overrides)
  end

  @doc """
  Returns the MCP tier (`:free | :pro | :max`) for the given user.

  Highest tier wins across all active subscriptions, so a user with both a
  Sanbase PRO and a SanAPI PRO sub gets `:max` (because SanAPI paid plans
  are MAX-tier for MCP).
  """
  @spec tier_for_user(User.t() | nil) :: :free | :pro | :max
  def tier_for_user(nil), do: :free

  def tier_for_user(%User{} = user) do
    case Subscription.user_subscriptions(user) do
      [] -> :free
      subs -> subs |> Enum.map(&tier_from_subscription/1) |> highest_tier()
    end
  end

  defp tier_from_subscription(%Subscription{plan: %Plan{} = plan}) do
    product = Product.code_by_id(plan.product_id)
    classify(product, plan.name)
  end

  defp tier_from_subscription(_), do: :free

  # SANBASE product
  defp classify("SANBASE", "FREE"), do: :free
  defp classify("SANBASE", "PRO"), do: :pro
  defp classify("SANBASE", "PRO_PLUS"), do: :max
  defp classify("SANBASE", "MAX"), do: :max
  defp classify("SANBASE", "BUSINESS_PRO"), do: :max
  defp classify("SANBASE", "BUSINESS_MAX"), do: :max
  defp classify("SANBASE", "CUSTOM"), do: :max
  defp classify("SANBASE", "PREMIUM"), do: :max
  defp classify("SANBASE", "CUSTOM_" <> _), do: :max
  defp classify("SANBASE", _), do: :free

  # SANAPI product — any paid plan is MAX-tier for MCP (per pricing decision).
  defp classify("SANAPI", "FREE"), do: :free
  defp classify("SANAPI", "BASIC"), do: :max
  defp classify("SANAPI", "PRO"), do: :max
  defp classify("SANAPI", "BUSINESS_PRO"), do: :max
  defp classify("SANAPI", "BUSINESS_MAX"), do: :max
  defp classify("SANAPI", "CUSTOM"), do: :max
  defp classify("SANAPI", "PREMIUM"), do: :max
  defp classify("SANAPI", "CUSTOM_" <> _), do: :max
  defp classify("SANAPI", _), do: :free

  defp classify(_, _), do: :free

  defp highest_tier([]), do: :free
  defp highest_tier(tiers), do: Enum.max_by(tiers, &tier_rank/1)

  defp tier_rank(:free), do: 0
  defp tier_rank(:pro), do: 1
  defp tier_rank(:max), do: 2
end
