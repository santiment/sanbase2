defmodule SanbaseWeb.MetricsAccessFormat do
  @moduledoc """
  Pure functions turning metric access values (days of history / delay, minimum
  plan) into the labels shown on the metrics access page.

  Every label comes in a full form ("Last year · 30-day delay", shown in the plan
  view, on hover and to screen readers) and, for windows, a compact code
  ("1y · 30d delay") for the narrow cells of the compare view.
  """

  alias Sanbase.Billing.Plan.PlanMetricAccess

  @type mode :: :relative | :exact
  @type days :: pos_integer() | nil

  @doc "Label for how far back the data is available."
  @spec history(days(), mode(), Date.t()) :: String.t()
  def history(nil, _mode, _today), do: "All history"
  def history(days, :exact, today) when is_integer(days), do: "Since " <> days_ago(days, today)

  def history(days, :relative, _today) when is_integer(days) do
    case whole_years(days) do
      1 -> "Last year"
      nil -> "Last #{days} days"
      years -> "Last #{years} years"
    end
  end

  @doc "Label for how far the plan holds back the newest data."
  @spec delay(days(), mode(), Date.t()) :: String.t()
  def delay(nil, _mode, _today), do: "No delay"
  def delay(days, :relative, _today) when is_integer(days), do: "#{days}-day delay"
  def delay(days, :exact, today) when is_integer(days), do: "Until " <> days_ago(days, today)

  @doc ~s(Compact `history/3`, about a bar wide: "All", "2y", "90d" or "since Nov '24".)
  @spec history_code(days(), mode(), Date.t()) :: String.t()
  def history_code(nil, _mode, _today), do: "All"

  def history_code(days, :exact, today) when is_integer(days),
    do: "since " <> Calendar.strftime(Date.add(today, -days), "%b '%y")

  def history_code(days, :relative, _today) when is_integer(days) do
    case whole_years(days) do
      nil -> "#{days}d"
      years -> "#{years}y"
    end
  end

  @doc ~s(Compact `delay/3`: "30d", a duration in both modes. No delay has no code: nil.)
  @spec delay_code(days(), mode(), Date.t()) :: String.t() | nil
  def delay_code(nil, _mode, _today), do: nil
  def delay_code(days, _mode, _today) when is_integer(days), do: "#{days}d"

  @doc "The full text of an access value."
  @spec label(PlanMetricAccess.access(), mode(), Date.t()) :: String.t()
  def label({:window, history, delay}, mode, today),
    do: history(history, mode, today) <> " · " <> delay(delay, mode, today)

  def label({:locked, plan_key}, _mode, _today), do: locked(plan_key)

  @doc """
  The compact text under a bar, in two parts that sit under its two halves:
  `{history, delay}` - "2y", "1y", "All" or "since Nov '24" on the left (exact
  dates); "30d", or an em dash for no delay, on the right ("All" keeps a lone
  "30d" from reading as 30 days of history). `:full` (all history, no delay)
  and `:locked` span both halves.
  """
  @spec code_parts(PlanMetricAccess.access(), mode(), Date.t()) ::
          :full | :locked | {String.t(), String.t()}
  def code_parts({:window, nil, nil}, _mode, _today), do: :full

  def code_parts({:window, history, delay}, mode, today),
    do: {history_code(history, mode, today), delay_code(delay, mode, today) || "—"}

  def code_parts({:locked, _plan_key}, _mode, _today), do: :locked

  @doc ~s(`code_parts/3` as one string: "Full", "2y · —", "1y · 30d", "Locked".)
  @spec code(PlanMetricAccess.access(), mode(), Date.t()) :: String.t()
  def code(access, mode, today) do
    case code_parts(access, mode, today) do
      :full -> "Full"
      :locked -> "Locked"
      {history, delay} -> history <> " · " <> delay
    end
  end

  @doc """
  Label for a metric locked in the selected plan. `nil` means no listed plan
  unlocks it; the page does not sell custom plans, so it is plainly "Locked".
  """
  @spec locked(String.t() | nil) :: String.t()
  def locked(nil), do: "Locked"
  def locked(plan_key) when is_binary(plan_key), do: "Requires " <> plan_label(plan_key)

  @doc """
  The two lines of the note on how access differs between the Sanbase web app
  and the API. The first names only the limits Sanbase Pro really has through
  the API: a shorter history and delayed data (its API window,
  `PlanMetricAccess.headline/2`), a low API call allowance (fewer monthly calls
  than Business Pro). With none of them, that sentence is left out, so the note
  cannot drift from the access checkers or the call limits.
  """
  @spec access_note(%{
          pro_api: {days(), days()},
          pro_calls: non_neg_integer(),
          business_calls: non_neg_integer()
        }) :: %{web_app: String.t(), api: String.t()}
  def access_note(%{pro_api: {history, delay}, pro_calls: pro, business_calls: business}) do
    limits =
      [
        not is_nil(history) && "a shorter history",
        not is_nil(delay) && "delayed data",
        pro < business && "a low API call allowance"
      ]
      |> Enum.filter(& &1)

    web_app =
      case limits do
        [] ->
          "Sanbase plans are built for the web app."

        limits ->
          "Sanbase plans are built for the web app. Through the API, Sanbase Pro gives " <>
            "only limited access: #{join_naturally(limits)}, so it isn't suited for API use."
      end

    %{
      web_app: web_app,
      api: "Business plans are built for the API and also give access to the Sanbase web app."
    }
  end

  # ["a", "b", "c"] => "a, b and c"
  defp join_naturally([only]), do: only

  defp join_naturally(items) do
    {init, [last]} = Enum.split(items, -1)
    Enum.join(init, ", ") <> " and " <> last
  end

  defp whole_years(days) when days > 0 and rem(days, 365) == 0, do: div(days, 365)
  defp whole_years(_days), do: nil

  defp days_ago(days, today), do: today |> Date.add(-days) |> Date.to_iso8601()

  @doc "The display label of a plan key."
  @spec plan_label(String.t()) :: String.t()
  def plan_label(plan_key), do: plan!(plan_key).label

  defp plan!(plan_key) do
    Enum.find(PlanMetricAccess.plans(), &(&1.key == plan_key)) ||
      raise ArgumentError, "unknown plan key: #{inspect(plan_key)}"
  end
end
