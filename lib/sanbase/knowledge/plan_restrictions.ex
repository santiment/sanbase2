defmodule Sanbase.Knowledge.PlanRestrictions do
  @moduledoc """
  The SanAPI data-access restriction matrix, rendered as an answer-prompt section.

  The numbers live in `Sanbase.Billing.Plan.ApiAccessChecker`, not in the Academy
  or the FAQ, so the prompt carries them as generated ground truth instead of
  prose copies that drift. They are what lets the model diagnose a reported data
  window — a FREE-tier window on a paid key means the requests are not
  authenticated as that subscription — instead of deflecting to support.

  Included unconditionally: the questions that need it are the ones where
  retrieval surfaced nothing about access. ~2.9 KB and static, so it sits inside
  the prompt's cacheable prefix.

  CUSTOM, bundle and package-based plans get no rows — they resolve per contract
  through other checkers — and are named in the section text instead. Per-metric
  exemptions are described in words rather than enumerated: that classification
  lives in the metric registry and reading it would put a query on the
  prompt-building path.

  The listed plans are hand-maintained: `ApiAccessChecker` matches plan names in
  `case` clauses and exposes no `known_plans/0`. Not every clause is a sellable
  plan — PRO_PLUS and MAX are only sold on product SANBASE, and their SANAPI
  cut-off clause returns the history depth, so they get no SanAPI rows. A cut-off
  of `nil` and one of `0` both mean nothing is withheld.
  """

  alias Sanbase.Billing.Plan.ApiAccessChecker

  @rows [
    {"No API key sent, or SanAPI FREE", "SANAPI", "FREE"},
    {"SanAPI BASIC", "SANAPI", "BASIC"},
    {"SanAPI PRO", "SANAPI", "PRO"},
    {"SanAPI BUSINESS_PRO", "SANAPI", "BUSINESS_PRO"},
    {"SanAPI BUSINESS_MAX", "SANAPI", "BUSINESS_MAX"},
    {"SanAPI INSTITUTIONAL", "SANAPI", "INSTITUTIONAL"},
    {"SanAPI ENTERPRISE", "SANAPI", "ENTERPRISE"},
    {"Sanbase BASIC", "SANBASE", "BASIC"},
    {"Sanbase PRO", "SANBASE", "PRO"},
    {"Sanbase PRO_PLUS", "SANBASE", "PRO_PLUS"},
    {"Sanbase MAX", "SANBASE", "MAX"}
  ]

  @type row :: %{
          label: String.t(),
          subscription_product: String.t(),
          plan: String.t(),
          historical_data_in_days: non_neg_integer() | nil,
          realtime_data_cut_off_in_days: non_neg_integer() | nil
        }

  @doc """
  The restriction matrix as data: one map per listed plan, with the two limits
  read from `ApiAccessChecker`.

  ## Examples

      iex> alias Sanbase.Knowledge.PlanRestrictions
      iex> free = Enum.find(PlanRestrictions.list_rows(), &(&1.plan == "FREE"))
      iex> {free.historical_data_in_days, free.realtime_data_cut_off_in_days}
      {365, 30}
  """
  @spec list_rows() :: [row()]
  def list_rows() do
    Enum.map(@rows, fn {label, subscription_product, plan} ->
      %{
        label: label,
        subscription_product: subscription_product,
        plan: plan,
        historical_data_in_days:
          ApiAccessChecker.historical_data_in_days(subscription_product, plan),
        realtime_data_cut_off_in_days:
          ApiAccessChecker.realtime_data_cut_off_in_days(subscription_product, plan)
      }
    end)
  end

  @doc """
  The body of the prompt section: the matrix, how to read it and how to use it as
  a diagnostic. Interpolated verbatim into the answer prompt; the enclosing
  `<SanAPI_Data_Access_Restrictions>` tags are written at the call site in
  `Sanbase.Knowledge.generate_initial_prompt/2`.

  ## Examples

      iex> section = Sanbase.Knowledge.PlanRestrictions.render_inner_section()
      iex> section =~ "| SanAPI BUSINESS_MAX | unlimited | none | full history, up to now |"
      true
  """
  @spec render_inner_section() :: String.t()
  def render_inner_section() do
    rows = list_rows()

    """
    Authoritative product configuration, generated directly from Santiment's access-control code.
    Where it disagrees with prose in the FAQ / Academy / Insight blocks below, THIS is correct — the
    prose is a hand-maintained copy and can be out of date. This block is not a citable source, so
    state these facts without a citation id.

    Two independent limits apply to every RESTRICTED metric:
      - history depth — how far back the returned data starts;
      - realtime cut-off — how much of the most recent data is withheld.
    A restricted metric therefore returns data only in [today - history, today - cut_off].

    Metrics classified as freely available are exempt from BOTH limits: they return full history up to
    now on every plan, including with no API key at all. This is why a single API key can legitimately
    show full history for some metrics and a narrow window for others.

    "Sanbase ..." rows are web-app subscriptions whose owner calls the API; their window differs from
    the SanAPI plan of the same name.

    #{table(rows)}

    CUSTOM, bundle and package-based plans are configured per contract and are NOT in this table — if
    the user is on one, say the window has to be looked up for their specific plan.

    #{diagnostic_note(rows)}
    """
  end

  defp table(rows) do
    header = [
      "| Subscription | History depth | Realtime cut-off | Window for restricted metrics |",
      "|---|---|---|---|"
    ]

    body =
      Enum.map(rows, fn row ->
        "| #{row.label} | #{format_history(row.historical_data_in_days)} | " <>
          "#{format_cut_off(row.realtime_data_cut_off_in_days)} | " <>
          "#{window(row.historical_data_in_days, row.realtime_data_cut_off_in_days)} |"
      end)

    Enum.join(header ++ body, "\n")
  end

  defp diagnostic_note(rows) do
    free = Enum.find(rows, &(&1.plan == "FREE"))
    history = free.historical_data_in_days
    cut_off = free.realtime_data_cut_off_in_days || 0

    """
    Diagnostic use — the window a user REPORTS tells you which plan their requests are actually being
    served as, regardless of what they are paying for:
      - A window roughly #{history - cut_off} days wide that ends roughly #{cut_off} days before today is the
        FREE-tier signature (#{history}-day history minus a #{cut_off}-day realtime cut-off).
      - Full history on some metrics AND a FREE-tier window on the rest, from the SAME key, means the
        key is being served as FREE: the unrestricted metrics are exempt from the limits, so they look
        fine while every restricted metric is clipped.
      - If a user on a paid plan reports a window from a lower plan, the most likely cause is that
        their requests are not being authenticated as their subscription, NOT that the metrics need
        extra permissions. Troubleshooting below lists the causes and the queries that confirm them.
    """
  end

  defp format_history(nil), do: "unlimited"
  defp format_history(days), do: "#{days} d"

  defp format_cut_off(cut_off) when cut_off in [nil, 0], do: "none"
  defp format_cut_off(days), do: "#{days} d"

  defp window(nil, cut_off) when cut_off in [nil, 0], do: "full history, up to now"
  defp window(nil, cut_off), do: "full history, ending #{cut_off} d ago"

  defp window(history, cut_off) when cut_off in [nil, 0], do: "last #{history} d, up to now"

  defp window(history, cut_off),
    do: "#{history - cut_off} d wide: from #{history} d ago to #{cut_off} d ago"
end
