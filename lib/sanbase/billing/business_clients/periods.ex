defmodule Sanbase.Billing.BusinessClients.Periods do
  @moduledoc ~s"""
  The arithmetic behind the Business Clients numbers, over plain line maps - no
  database access, so every rule can be tested on hand-made lines.

  A line is a map with at least:

    * `:period_start`, `:period_end` - `Date`s; the line pays for
      `period_start <= day < period_end`, the way Stripe reports periods
    * `:amount` - cents, excluding tax
    * `:proration` - boolean
    * `:subscription` - the Stripe subscription id of the invoice, or anything unique
      for a line outside a subscription

  and optionally `:interval` (`"month"` or `"year"`) for the renewal rules and `:kind`
  (`:business` or `:email`) for the segments.

  Only *countable* lines - not a proration and a positive amount - say whether a client
  is active and what they pay per month. A proration settles a change in the middle
  of a period and a `$0` line is a trial or a full discount; neither is a recurring
  price.
  """

  @days_per_month 30.44

  @segments [:plan, :business_email]

  @type line :: %{
          required(:period_start) => Date.t(),
          required(:period_end) => Date.t(),
          required(:amount) => integer(),
          required(:proration) => boolean(),
          required(:subscription) => term(),
          optional(atom()) => term()
        }

  @doc ~s"""
  Whether the line is a recurring payment: not a proration and a positive amount.
  """
  @spec countable?(line()) :: boolean()
  def countable?(%{proration: false, amount: amount, period_start: %Date{}, period_end: %Date{}})
      when amount > 0,
      do: true

  def countable?(_line), do: false

  @doc ~s"""
  How many months the line's period spans: `round(days / 30.44)`, at least 1.
  """
  @spec months(line()) :: pos_integer()
  def months(%{period_start: from, period_end: to}) do
    max(1, round(Date.diff(to, from) / @days_per_month))
  end

  @doc ~s"""
  The line's amount spread over the months of its period, in cents.
  """
  @spec monthly_value(line()) :: integer()
  def monthly_value(line), do: round(line.amount / months(line))

  @doc ~s"""
  Whether the line's period contains the date.
  """
  @spec covers?(line(), Date.t()) :: boolean()
  def covers?(%{period_start: from, period_end: to}, date) do
    Date.compare(from, date) != :gt and Date.compare(date, to) == :lt
  end

  @doc ~s"""
  The countable lines in force on the date, one per subscription.

  Within a subscription the line that started last wins: after an upgrade both the
  old and the new period contain the date, and only the new price is being paid.
  """
  @spec current_lines([line()], Date.t()) :: [line()]
  def current_lines(lines, date) do
    lines
    |> Enum.filter(&(countable?(&1) and covers?(&1, date)))
    |> Enum.group_by(& &1.subscription)
    |> Enum.map(fn {_subscription, group} ->
      Enum.max_by(group, &{Date.to_gregorian_days(&1.period_start), &1.amount})
    end)
  end

  @doc ~s"""
  Whether any countable line covers the date.
  """
  @spec active?([line()], Date.t()) :: boolean()
  def active?(lines, date), do: current_lines(lines, date) != []

  @doc ~s"""
  Monthly recurring revenue on the date, in cents: the monthly value of every line in
  force, summed over subscriptions.
  """
  @spec mrr([line()], Date.t()) :: integer()
  def mrr(lines, date) do
    lines |> current_lines(date) |> Enum.map(&monthly_value/1) |> Enum.sum()
  end

  @doc ~s"""
  The segments the metrics are split into: `:plan` and `:business_email`.
  """
  @spec segments() :: [:plan | :business_email]
  def segments, do: @segments

  @doc ~s"""
  A user's segment on the date: `:plan` when a line in force is of a business plan
  (`kind: :business`), otherwise `:business_email` - an email-plan line counted by the
  email rule or an admin override.
  """
  @spec segment([line()], Date.t()) :: :plan | :business_email
  def segment(lines, date) do
    if Enum.any?(current_lines(lines, date), &(&1[:kind] == :business)),
      do: :plan,
      else: :business_email
  end

  @doc ~s"""
  A line's segment: `:plan` for a business plan line, `:business_email` for any other.
  """
  @spec line_segment(line()) :: :plan | :business_email
  def line_segment(line), do: if(line[:kind] == :business, do: :plan, else: :business_email)

  @doc ~s"""
  The date `months` months before `date`, clamped to the end of a shorter month.
  """
  @spec months_before(Date.t(), non_neg_integer()) :: Date.t()
  def months_before(date, months), do: Date.shift(date, month: -months)

  @doc ~s"""
  Client and revenue churn over a rolling window.

  `lines_by_user` maps a user to their business lines. The cohort is every user
  active on `as_of - window_months`. A cohort member not active on `as_of` is lost;
  for revenue, each member contributes `max(0, mrr_then - mrr_now)`, so a downgrade
  counts as lost revenue and an upgrade does not offset someone else's loss - it is
  reported separately as `expansion_mrr`.

  Rates are fractions, `nil` when the cohort is empty.
  """
  @spec churn(%{term() => [line()]}, Date.t(), pos_integer()) :: %{
          client: %{rate: float() | nil, lost: non_neg_integer(), base: non_neg_integer()},
          revenue: %{
            rate: float() | nil,
            lost_mrr: non_neg_integer(),
            base_mrr: non_neg_integer(),
            expansion_mrr: non_neg_integer()
          }
        }
  def churn(lines_by_user, as_of, window_months) do
    cohort_date = months_before(as_of, window_months)

    cohort =
      for {_user, lines} <- lines_by_user, active?(lines, cohort_date) do
        {mrr(lines, cohort_date), mrr(lines, as_of)}
      end

    lost = Enum.count(cohort, fn {_then, now} -> now == 0 end)
    base = length(cohort)

    %{
      client: %{rate: ratio(lost, base), lost: lost, base: base},
      revenue: revenue_churn(cohort)
    }
  end

  # Over `{mrr_then, mrr_now}` per cohort member.
  defp revenue_churn(cohort) do
    base_mrr = Enum.sum_by(cohort, &elem(&1, 0))
    lost_mrr = Enum.sum_by(cohort, fn {then, now} -> max(0, then - now) end)
    expansion_mrr = Enum.sum_by(cohort, fn {then, now} -> max(0, now - then) end)

    %{
      rate: ratio(lost_mrr, base_mrr),
      lost_mrr: lost_mrr,
      base_mrr: base_mrr,
      expansion_mrr: expansion_mrr
    }
  end

  @doc ~s"""
  The users who churned within a rolling window: active on at least one day of
  `[as_of - window_months, as_of)` and not active on `as_of`. That is, a countable
  line ended within `(as_of - window_months, as_of]` and none covers `as_of`. Unlike
  `churn/3` this includes users who joined and left within the window.

  Per user: `:user` (the key of `lines_by_user`), `:churned_on` - the latest end of a
  line that ended by `as_of`, the first day not covered - `:last_lines`, the lines in
  force on the day before, `:lost_mrr`, their MRR then, and `:joined_on`, the start of
  the first countable line. Latest `churned_on` first.
  """
  @spec churned(%{term() => [line()]}, Date.t(), pos_integer()) :: [
          %{
            user: term(),
            churned_on: Date.t(),
            last_lines: [line()],
            lost_mrr: non_neg_integer(),
            joined_on: Date.t()
          }
        ]
  def churned(lines_by_user, as_of, window_months) do
    window_start = months_before(as_of, window_months)

    for {user, lines} <- lines_by_user,
        countable = Enum.filter(lines, &countable?/1),
        ended = Enum.filter(countable, &ended_within?(&1, window_start, as_of)),
        ended != [],
        not active?(countable, as_of) do
      churned_on = ended |> Enum.map(& &1.period_end) |> Enum.max(Date)
      last_lines = current_lines(countable, Date.add(churned_on, -1))

      %{
        user: user,
        churned_on: churned_on,
        last_lines: last_lines,
        lost_mrr: last_lines |> Enum.map(&monthly_value/1) |> Enum.sum(),
        joined_on: countable |> Enum.map(& &1.period_start) |> Enum.min(Date)
      }
    end
    |> Enum.sort_by(& &1.churned_on, {:desc, Date})
  end

  @doc ~s"""
  Client and revenue renewal over a rolling window.

  A countable line whose `:interval` is in `intervals` is *due* when its period ended
  within `(as_of - window_months, as_of]` and either the grace period after the end
  has passed by `as_of` or it already renewed. A period still inside its grace and not
  renewed is pending and left out - it may yet renew.

  A due line *renewed* when another countable line of the same user starts within
  `grace_days` after its end, or covers the day after its end (an early renewal or an
  upgrade). The first such line is the renewal.

  Revenue renewal compares ACV (`monthly_value * 12`): the renewals' new ACV over the
  due lines' old ACV. With `upgrades_full_value: false` each new ACV is capped at the
  old one, so upgrades cannot lift the rate above what was due.

  With `:segment` only the due lines of that segment (`line_segment/1`) count; the
  renewal may still be a line of the other segment.

  Options: `:window_months`, `:intervals`, `:grace_days`, `:upgrades_full_value`,
  `:segment` (default `nil`, every line).
  """
  @spec renewal(%{term() => [line()]}, Date.t(), Keyword.t()) :: %{
          client: %{
            rate: float() | nil,
            renewed: non_neg_integer(),
            due: non_neg_integer()
          },
          revenue: %{
            rate: float() | nil,
            renewed_acv: non_neg_integer(),
            due_acv: non_neg_integer()
          }
        }
  def renewal(lines_by_user, as_of, opts) do
    due = due_periods(lines_by_user, as_of, opts)

    renewed = Enum.count(due, &elem(&1, 0))
    due_acv = Enum.sum_by(due, &elem(&1, 1))
    renewed_acv = Enum.sum_by(due, &elem(&1, 2))

    %{
      client: %{rate: ratio(renewed, length(due)), renewed: renewed, due: length(due)},
      revenue: %{rate: ratio(renewed_acv, due_acv), renewed_acv: renewed_acv, due_acv: due_acv}
    }
  end

  @doc ~s"""
  Annual contract value of a line: its monthly value times 12.
  """
  @spec acv(line()) :: integer()
  def acv(line), do: monthly_value(line) * 12

  # `{renewed?, old ACV, new ACV}` for every period due on `as_of`.
  defp due_periods(lines_by_user, as_of, opts) do
    window_start = months_before(as_of, Keyword.fetch!(opts, :window_months))
    intervals = Keyword.fetch!(opts, :intervals)
    grace_days = Keyword.fetch!(opts, :grace_days)
    full_value? = Keyword.get(opts, :upgrades_full_value, true)
    segment = Keyword.get(opts, :segment)

    for {_user, lines} <- lines_by_user,
        countable = Enum.filter(lines, &countable?/1),
        line <- countable,
        line[:interval] in intervals,
        segment == nil or line_segment(line) == segment,
        ended_within?(line, window_start, as_of),
        # A one-element generator, so a `nil` renewal is bound instead of filtering.
        renewal <- [renewal_line(line, countable, grace_days, as_of)],
        renewal != nil or past_grace?(line, grace_days, as_of) do
      {renewal != nil, acv(line), renewed_acv(line, renewal, full_value?)}
    end
  end

  # Whether the period ended within `(window_start, as_of]`.
  defp ended_within?(line, window_start, as_of) do
    Date.compare(line.period_end, window_start) == :gt and
      Date.compare(line.period_end, as_of) != :gt
  end

  defp past_grace?(line, grace_days, as_of), do: Date.diff(as_of, line.period_end) >= grace_days

  defp renewed_acv(_line, nil, _full_value?), do: 0
  defp renewed_acv(_line, renewal, true), do: acv(renewal)
  defp renewed_acv(line, renewal, false), do: min(acv(renewal), acv(line))

  # The first line, known by `as_of`, that continues `line` past its end.
  defp renewal_line(line, lines, grace_days, as_of) do
    day_after = Date.add(line.period_end, 1)
    grace_end = Date.add(line.period_end, grace_days)

    lines
    |> Enum.reject(&(&1 == line or Date.compare(&1.period_start, as_of) == :gt))
    |> Enum.filter(fn other ->
      starts_in_grace? =
        Date.compare(other.period_start, line.period_end) != :lt and
          Date.compare(other.period_start, grace_end) != :gt

      # Only a line that started after this one can continue it; a parallel older
      # subscription that happens to run past the end is not a renewal.
      continues? =
        Date.compare(other.period_start, line.period_start) == :gt and
          covers?(other, day_after)

      starts_in_grace? or continues?
    end)
    |> Enum.min_by(&Date.to_gregorian_days(&1.period_start), fn -> nil end)
  end

  defp ratio(_part, 0), do: nil
  defp ratio(part, whole), do: part / whole
end
