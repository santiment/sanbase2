defmodule Sanbase.Billing.BusinessClients.PlanLimit do
  @moduledoc ~s"""
  How much of the monthly API call limit a client uses, and whether that makes them a
  candidate for a bigger plan. No database access - the caller passes the calls per
  month and the limit.

  A client is an upsell candidate when either:

    * they used 80% or more of the limit in 2 or more of the last 6 full months, and
      still 50% or more last month or at this month's pace; or
    * this month's pace reaches 90% of the limit, once at least 7 days of the month
      have passed.

  The pace is the calls so far this month spread over the whole month.
  """

  @high_share 0.8
  @high_months 2
  @window_months 6
  @still_share 0.5
  @pace_share 0.9
  @min_pace_days 7

  @type month_share :: %{month: Date.t(), calls: non_neg_integer(), share: float() | nil}
  @type t :: %{
          limit: pos_integer() | :unlimited | nil,
          months: [month_share()],
          last_month: month_share(),
          pace: %{calls: non_neg_integer(), share: float() | nil, partial?: boolean()},
          months_at_high: non_neg_integer(),
          upsell?: boolean(),
          upsell_reason: String.t() | nil
        }

  @doc ~s"""
  The limit use of one client on `today`, from their calls per calendar month
  (`%{first_day_of_month => calls}`) and their monthly limit (`nil` when unknown).

  `months` lists the last #{@window_months} full months, oldest first. Shares are `nil`
  without a numeric limit, and so is every upsell signal.
  """
  @spec assess(%{Date.t() => non_neg_integer()}, pos_integer() | :unlimited | nil, Date.t()) ::
          t()
  def assess(calls_by_month, limit, today) do
    this_month = Date.beginning_of_month(today)

    months =
      for back <- @window_months..1//-1 do
        month = Date.shift(this_month, month: -back)
        calls = Map.get(calls_by_month, month, 0)
        %{month: month, calls: calls, share: share(calls, limit)}
      end

    so_far = Map.get(calls_by_month, this_month, 0)
    pace_calls = round(so_far / today.day * Date.days_in_month(today))
    partial? = today.day < @min_pace_days
    pace = %{calls: pace_calls, share: share(pace_calls, limit), partial?: partial?}

    last_month = List.last(months)
    months_at_high = Enum.count(months, &at_least?(&1.share, @high_share))
    reason = upsell_reason(months_at_high, last_month, pace)

    %{
      limit: limit,
      months: months,
      last_month: last_month,
      pace: pace,
      months_at_high: months_at_high,
      upsell?: reason != nil,
      upsell_reason: reason
    }
  end

  defp upsell_reason(months_at_high, last_month, pace) do
    recent_pace = if pace.partial?, do: nil, else: pace.share

    cond do
      at_least?(recent_pace, @pace_share) ->
        "On pace for #{percent(pace.share)} of the monthly limit this month"

      months_at_high >= @high_months and
          (at_least?(last_month.share, @still_share) or at_least?(recent_pace, @still_share)) ->
        "Used #{percent(@high_share)} or more of the monthly limit in #{months_at_high} of " <>
          "the last #{@window_months} months"

      true ->
        nil
    end
  end

  defp share(calls, limit) when is_integer(limit) and limit > 0, do: calls / limit
  defp share(_calls, _limit), do: nil

  defp at_least?(share, threshold) when is_float(share), do: share >= threshold
  defp at_least?(_share, _threshold), do: false

  @doc ~s"""
  A share as a whole percentage, e.g. `0.873` as `"87%"`.
  """
  @spec percent(float() | nil) :: String.t()
  def percent(nil), do: "-"
  def percent(share), do: "#{round(share * 100)}%"
end
