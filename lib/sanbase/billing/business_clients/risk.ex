defmodule Sanbase.Billing.BusinessClients.Risk do
  @moduledoc ~s"""
  The automatic risk level of a business client: `:high_risk`, `:at_risk` or
  `:healthy`, with the reasons behind it. No database access - the caller passes the
  facts, so every rule can be tested on hand-made maps.

  The rules come from the cancellations of the two years before November 2026: which
  clients clicked cancel in the 30 days after a week in which they looked a certain
  way. They rank clients, they do not predict - most High Risk clients stay.

  A client is described by:

    * `:segment` - `:plan` for a business plan, `:business_email` for a plan counted
      by the email rule or an override
    * `:interval` - `"month"` or `"year"`
    * `:tenure_days` - days since the first paid period started
    * `:active_days` - `{current, previous}`, the days with any API or web activity in
      the usage window and in the window before it; `nil` when unknown
    * `:api_calls` - `{current, previous}` API key calls in the same windows; either
      may be `nil` when unknown
    * `:days_to_renewal` - days until the renewal date, `nil` when there is none

  Monthly clients are scored on tenure and usage. Yearly clients are too few to score
  on usage and are only flagged ahead of their renewal.

  Business plan, monthly:

    * High Risk - active on at most `risk_high_active_days` days, or a new client
      whose usage dropped
    * At Risk - a new client, or active on at most `risk_low_active_days` days, or
      usage dropped

  Business email, monthly:

    * High Risk - no activity, or a new client active on at most
      `risk_low_active_days` days
    * At Risk - a new client, or active on at most `risk_high_active_days` days

  A new client is within `risk_new_client_days` of the first paid period. Usage
  dropped when API key calls or active days fell by `risk_usage_drop_percent` or more
  against the previous window; a previous window below 100 calls or 5 active days
  is too small to compare with.
  """

  @min_calls_for_drop 100
  @min_active_days_for_drop 5

  @type level :: :high_risk | :at_risk | :healthy | :unknown
  @type facts :: %{
          required(:segment) => :plan | :business_email,
          required(:interval) => String.t() | nil,
          required(:tenure_days) => integer() | nil,
          required(:active_days) => {non_neg_integer(), non_neg_integer()} | nil,
          required(:api_calls) => {non_neg_integer() | nil, non_neg_integer() | nil},
          required(:days_to_renewal) => integer() | nil
        }

  @doc ~s"""
  The level and its reasons, most severe first. `:unknown` when the usage a monthly
  client is scored on could not be read.
  """
  @spec assess(facts(), map()) :: %{level: level(), reasons: [String.t()]}
  def assess(%{interval: "year"} = facts, settings) do
    facts.days_to_renewal |> renewal_signals(settings) |> result()
  end

  def assess(%{active_days: nil}, _settings) do
    %{level: :unknown, reasons: ["Usage data is not available"]}
  end

  def assess(%{segment: :plan} = facts, settings) do
    {active, _previous} = facts.active_days
    new? = new_client?(facts, settings)
    drop = usage_drop(facts, settings)

    [
      active_signal(active, settings, :high_risk, settings.risk_high_active_days) ||
        active_signal(active, settings, :at_risk, settings.risk_low_active_days),
      tenure_and_drop_signal(new?, drop, facts)
    ]
    |> result()
  end

  def assess(facts, settings) do
    {active, _previous} = facts.active_days
    new? = new_client?(facts, settings)
    activity = activity_text(active, settings)

    signal =
      cond do
        active == 0 ->
          {:high_risk, activity}

        new? and active <= settings.risk_low_active_days ->
          {:high_risk, "#{new_client_text(facts)}, #{downcase_first(activity)}"}

        new? ->
          {:at_risk, new_client_text(facts)}

        active <= settings.risk_high_active_days ->
          {:at_risk, activity}

        true ->
          nil
      end

    result([signal])
  end

  defp renewal_signals(days, settings) when is_integer(days) do
    if days <= settings.risk_renewal_days, do: [{:at_risk, renewal_text(days)}], else: []
  end

  defp renewal_signals(_days, _settings), do: []

  defp renewal_text(days) when days < 0, do: "Renewal was due #{-days} day(s) ago"
  defp renewal_text(0), do: "Renews today"
  defp renewal_text(days), do: "Renews in #{days} day(s)"

  defp active_signal(active, settings, level, threshold) do
    if active <= threshold, do: {level, activity_text(active, settings)}
  end

  defp tenure_and_drop_signal(true, {_percent, _what} = drop, facts),
    do: {:high_risk, "#{new_client_text(facts)} with usage down #{drop_text(drop)}"}

  defp tenure_and_drop_signal(true, nil, facts), do: {:at_risk, new_client_text(facts)}

  defp tenure_and_drop_signal(false, {_percent, _what} = drop, _facts),
    do: {:at_risk, "Usage down #{drop_text(drop)}"}

  defp tenure_and_drop_signal(false, nil, _facts), do: nil

  defp drop_text({percent, what}), do: "#{percent}% (#{what})"

  defp new_client?(%{tenure_days: days}, settings) when is_integer(days),
    do: days <= settings.risk_new_client_days

  defp new_client?(_facts, _settings), do: false

  # The larger of the two drops, as `{percent, what dropped}`, when it reaches the
  # threshold.
  defp usage_drop(facts, settings) do
    {calls, calls_previous} = facts.api_calls
    {active, active_previous} = facts.active_days

    [
      {drop_percent(calls, calls_previous, @min_calls_for_drop), "API calls"},
      {drop_percent(active, active_previous, @min_active_days_for_drop), "active days"}
    ]
    |> Enum.reject(fn {percent, _what} -> is_nil(percent) end)
    |> Enum.max_by(fn {percent, _what} -> percent end, fn -> nil end)
    |> case do
      {percent, _what} = drop when percent >= settings.risk_usage_drop_percent -> drop
      _ -> nil
    end
  end

  defp drop_percent(current, previous, min_previous)
       when is_integer(current) and is_integer(previous) and previous >= min_previous,
       do: round((1 - current / previous) * 100)

  defp drop_percent(_current, _previous, _min_previous), do: nil

  defp activity_text(0, settings),
    do: "No activity in the last #{settings.usage_window_days} days"

  defp activity_text(active, settings),
    do: "Active on #{active} of the last #{settings.usage_window_days} days"

  defp new_client_text(%{tenure_days: days}), do: "New client (#{days} days)"

  defp downcase_first(<<first::utf8, rest::binary>>), do: String.downcase(<<first::utf8>>) <> rest

  # The most severe signal sets the level; the reasons list the signals, most severe
  # first.
  defp result(signals) do
    signals =
      signals
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn {level, _text} -> if level == :high_risk, do: 0, else: 1 end)

    level =
      case signals do
        [] -> :healthy
        [{level, _text} | _] -> level
      end

    %{level: level, reasons: Enum.map(signals, fn {_level, text} -> text end)}
  end
end
