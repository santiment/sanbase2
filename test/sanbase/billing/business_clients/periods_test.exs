defmodule Sanbase.Billing.BusinessClients.PeriodsTest do
  use ExUnit.Case, async: true

  alias Sanbase.Billing.BusinessClients.Periods

  @renewal_opts [
    window_months: 12,
    intervals: ["year"],
    grace_days: 30,
    upgrades_full_value: true
  ]

  defp line(from, to, amount, opts \\ []) do
    %{
      period_start: from,
      period_end: to,
      amount: amount,
      proration: Keyword.get(opts, :proration, false),
      subscription: Keyword.get(opts, :subscription, "sub_1"),
      interval: Keyword.get(opts, :interval, "month")
    }
  end

  defp yearly(from, amount, opts \\ []) do
    line(from, Date.shift(from, year: 1), amount, Keyword.put(opts, :interval, "year"))
  end

  describe "monthly value" do
    test "a month is one month, a year is twelve" do
      assert Periods.monthly_value(line(~D[2026-01-01], ~D[2026-02-01], 42_000)) == 42_000
      assert Periods.monthly_value(yearly(~D[2026-01-01], 1_200_000)) == 100_000
    end

    test "a short period counts as at least one month" do
      assert Periods.months(line(~D[2026-01-01], ~D[2026-01-05], 1_000)) == 1
      assert Periods.monthly_value(line(~D[2026-01-01], ~D[2026-01-05], 1_000)) == 1_000
    end

    test "a quarter is three months" do
      assert Periods.months(line(~D[2026-01-01], ~D[2026-04-01], 300)) == 3
    end
  end

  describe "active?/2 and mrr/2" do
    test "the period start is covered, the end is not" do
      lines = [line(~D[2026-01-01], ~D[2026-02-01], 42_000)]

      assert Periods.active?(lines, ~D[2026-01-01])
      assert Periods.active?(lines, ~D[2026-01-31])
      refute Periods.active?(lines, ~D[2026-02-01])
      refute Periods.active?(lines, ~D[2025-12-31])
    end

    test "prorations and $0 lines do not make a client active" do
      lines = [
        line(~D[2026-01-01], ~D[2026-02-01], 5_000, proration: true),
        line(~D[2026-01-01], ~D[2026-02-01], 0),
        line(~D[2026-01-01], ~D[2026-02-01], -3_000)
      ]

      refute Periods.active?(lines, ~D[2026-01-15])
      assert Periods.mrr(lines, ~D[2026-01-15]) == 0
    end

    test "after an upgrade only the newer line of the subscription counts" do
      lines = [
        yearly(~D[2026-01-01], 478_800),
        yearly(~D[2026-06-01], 1_138_800),
        line(~D[2026-06-01], ~D[2027-01-01], -200_000, proration: true)
      ]

      assert Periods.mrr(lines, ~D[2026-03-01]) == 39_900
      assert Periods.mrr(lines, ~D[2026-07-01]) == 94_900
    end

    test "two subscriptions add up" do
      lines = [
        line(~D[2026-01-01], ~D[2026-02-01], 42_000, subscription: "a"),
        line(~D[2026-01-10], ~D[2026-02-10], 4_900, subscription: "b")
      ]

      assert Periods.mrr(lines, ~D[2026-01-15]) == 46_900
    end

    test "lines without a period never count" do
      refute Periods.active?([line(nil, nil, 100)], ~D[2026-01-01])
    end
  end

  describe "churn/3" do
    @as_of ~D[2026-10-01]

    test "a cohort member not active today is lost, a newcomer is not in the cohort" do
      lines_by_user = %{
        stays: [yearly(~D[2025-09-01], 1_200_000), yearly(~D[2026-09-01], 1_200_000)],
        leaves: [yearly(~D[2025-01-01], 600_000)],
        new: [yearly(~D[2026-03-01], 1_200_000)]
      }

      churn = Periods.churn(lines_by_user, @as_of, 12)

      assert churn.client == %{rate: 0.5, lost: 1, base: 2}
      assert churn.revenue.base_mrr == 150_000
      assert churn.revenue.lost_mrr == 50_000
      assert churn.revenue.expansion_mrr == 0
      assert_in_delta churn.revenue.rate, 1 / 3, 1.0e-9
    end

    test "a plan switch is not churn and a downgrade counts only in revenue churn" do
      lines_by_user = %{
        switched: [
          yearly(~D[2025-09-01], 1_200_000, subscription: "old"),
          line(~D[2026-09-01], ~D[2026-10-15], 100_000, subscription: "new")
        ],
        downgraded: [
          line(~D[2025-09-15], ~D[2025-10-15], 99_900),
          line(~D[2026-09-15], ~D[2026-10-15], 42_000)
        ]
      }

      churn = Periods.churn(lines_by_user, @as_of, 12)

      assert churn.client == %{rate: 0.0, lost: 0, base: 2}
      assert churn.revenue.lost_mrr == 57_900
      assert churn.revenue.base_mrr == 199_900
    end

    test "an upgrade is expansion and does not offset another client's loss" do
      lines_by_user = %{
        upgraded: [
          line(~D[2025-09-15], ~D[2025-10-15], 42_000),
          line(~D[2026-09-15], ~D[2026-10-15], 99_900)
        ],
        lost: [line(~D[2025-09-15], ~D[2025-10-15], 42_000)]
      }

      churn = Periods.churn(lines_by_user, @as_of, 12)

      assert churn.revenue.lost_mrr == 42_000
      assert churn.revenue.expansion_mrr == 57_900
      assert churn.revenue.rate == 0.5
    end

    test "an empty cohort has no rate" do
      churn = Periods.churn(%{new: [yearly(~D[2026-03-01], 100)]}, @as_of, 12)

      assert churn.client == %{rate: nil, lost: 0, base: 0}
      assert churn.revenue.rate == nil
    end
  end

  describe "churned/3" do
    @as_of ~D[2026-10-01]

    test "who left within the window, latest first, with what they paid last" do
      lines_by_user = %{
        # A client since before the window who left in it, after an upgrade.
        left: [
          yearly(~D[2024-06-01], 600_000),
          line(~D[2025-06-01], ~D[2026-03-01], 270_000, subscription: "sub_2"),
          line(~D[2026-03-01], ~D[2026-06-01], 99_900),
          line(~D[2026-05-01], ~D[2026-06-01], 1_000, proration: true)
        ],
        # Joined and left within the window: not in the churn cohort, still churned.
        brief: [line(~D[2026-02-01], ~D[2026-03-01], 42_000)],
        active: [line(~D[2025-01-01], ~D[2025-02-01], 42_000), yearly(~D[2026-01-01], 1_200)],
        gone_before: [line(~D[2025-08-01], ~D[2025-09-01], 42_000)],
        switched: [
          line(~D[2026-01-01], ~D[2026-05-01], 160_000, subscription: "old"),
          line(~D[2026-05-01], ~D[2026-11-01], 600_000, subscription: "new")
        ],
        zero: [line(~D[2026-02-01], ~D[2026-03-01], 0)]
      }

      assert [left, brief] = Periods.churned(lines_by_user, @as_of, 12)

      assert left.user == :left
      assert left.churned_on == ~D[2026-06-01]
      assert left.lost_mrr == 33_300
      assert left.joined_on == ~D[2024-06-01]
      assert [%{amount: 99_900}] = left.last_lines

      assert brief.user == :brief
      assert brief.churned_on == ~D[2026-03-01]
      assert brief.lost_mrr == 42_000
      assert brief.joined_on == ~D[2026-02-01]
    end

    test "a line ending on the window start is outside it, one ending on as_of inside" do
      lines_by_user = %{
        edge_out: [line(~D[2025-09-01], ~D[2025-10-01], 1_000)],
        edge_in: [line(~D[2026-09-01], ~D[2026-10-01], 1_000)]
      }

      assert [%{user: :edge_in, churned_on: @as_of}] =
               Periods.churned(lines_by_user, @as_of, 12)
    end
  end

  describe "renewal/3" do
    test "a yearly period renewed on time" do
      lines_by_user = %{a: [yearly(~D[2025-03-01], 1_200_000), yearly(~D[2026-03-01], 1_200_000)]}

      renewal = Periods.renewal(lines_by_user, ~D[2026-10-01], @renewal_opts)

      assert renewal.client == %{rate: 1.0, renewed: 1, due: 1}
      assert renewal.revenue == %{rate: 1.0, renewed_acv: 1_200_000, due_acv: 1_200_000}
    end

    test "a renewal paid within the grace counts, one after it does not" do
      within = %{a: [yearly(~D[2025-03-01], 1_200_000), yearly(~D[2026-03-20], 1_200_000)]}
      late = %{a: [yearly(~D[2025-03-01], 1_200_000), yearly(~D[2026-05-01], 1_200_000)]}

      assert Periods.renewal(within, ~D[2026-10-01], @renewal_opts).client.renewed == 1

      late_renewal = Periods.renewal(late, ~D[2026-10-01], @renewal_opts)
      assert late_renewal.client == %{rate: 0.0, renewed: 0, due: 1}
      assert late_renewal.revenue.due_acv == 1_200_000
    end

    test "a period still inside its grace is pending, not due" do
      lines_by_user = %{a: [yearly(~D[2025-09-20], 1_200_000)]}

      renewal = Periods.renewal(lines_by_user, ~D[2026-10-01], @renewal_opts)

      assert renewal.client == %{rate: nil, renewed: 0, due: 0}
      # Once the grace has passed it is due and not renewed.
      assert Periods.renewal(lines_by_user, ~D[2026-10-25], @renewal_opts).client.due == 1
    end

    test "a pending period that already renewed is due and renewed" do
      lines_by_user = %{a: [yearly(~D[2025-09-20], 1_200_000), yearly(~D[2026-09-20], 1_200_000)]}

      assert Periods.renewal(lines_by_user, ~D[2026-10-01], @renewal_opts).client ==
               %{rate: 1.0, renewed: 1, due: 1}
    end

    test "monthly periods are not due when only yearly plans renew" do
      lines_by_user = %{a: [line(~D[2026-08-01], ~D[2026-09-01], 42_000)]}

      assert Periods.renewal(lines_by_user, ~D[2026-10-01], @renewal_opts).client.due == 0

      opts = Keyword.put(@renewal_opts, :intervals, ["month", "year"])
      assert Periods.renewal(lines_by_user, ~D[2026-10-01], opts).client.due == 1
    end

    test "an upgrade counts at full value unless capped" do
      lines_by_user = %{a: [yearly(~D[2025-03-01], 1_200_000), yearly(~D[2026-03-01], 2_400_000)]}

      full = Periods.renewal(lines_by_user, ~D[2026-10-01], @renewal_opts)
      assert full.revenue == %{rate: 2.0, renewed_acv: 2_400_000, due_acv: 1_200_000}

      capped_opts = Keyword.put(@renewal_opts, :upgrades_full_value, false)
      capped = Periods.renewal(lines_by_user, ~D[2026-10-01], capped_opts)
      assert capped.revenue == %{rate: 1.0, renewed_acv: 1_200_000, due_acv: 1_200_000}
    end

    test "a downgrade at renewal lowers revenue renewal" do
      lines_by_user = %{a: [yearly(~D[2025-03-01], 1_200_000), yearly(~D[2026-03-01], 600_000)]}

      renewal = Periods.renewal(lines_by_user, ~D[2026-10-01], @renewal_opts)
      assert renewal.client.rate == 1.0
      assert renewal.revenue.rate == 0.5
    end

    test "an upgrade in the middle of the year renews the old period" do
      lines_by_user = %{
        a: [
          yearly(~D[2025-03-01], 1_200_000),
          yearly(~D[2025-09-01], 2_400_000),
          line(~D[2025-09-01], ~D[2026-03-01], -600_000, proration: true)
        ]
      }

      renewal = Periods.renewal(lines_by_user, ~D[2026-08-01], @renewal_opts)
      assert renewal.client == %{rate: 1.0, renewed: 1, due: 1}
      assert renewal.revenue.renewed_acv == 2_400_000
    end

    test "a yearly period renewed by a monthly plan is renewed" do
      lines_by_user = %{
        a: [yearly(~D[2025-03-01], 1_200_000), line(~D[2026-03-01], ~D[2026-04-01], 42_000)]
      }

      renewal = Periods.renewal(lines_by_user, ~D[2026-10-01], @renewal_opts)
      assert renewal.client.renewed == 1
      assert renewal.revenue.renewed_acv == 504_000
    end

    test "a period that ended before the window is not due" do
      lines_by_user = %{a: [yearly(~D[2024-06-01], 1_200_000)]}

      assert Periods.renewal(lines_by_user, ~D[2026-10-01], @renewal_opts).client.due == 0
    end

    test "a parallel older subscription is not a renewal" do
      lines_by_user = %{
        a: [
          yearly(~D[2024-06-01], 100_000, subscription: "other")
          |> Map.put(:period_end, ~D[2027-06-01]),
          yearly(~D[2025-03-01], 1_200_000)
        ]
      }

      assert Periods.renewal(lines_by_user, ~D[2026-10-01], @renewal_opts).client ==
               %{rate: 0.0, renewed: 0, due: 1}
    end
  end

  describe "segments" do
    @as_of ~D[2026-10-01]

    defp plan(line), do: Map.put(line, :kind, :business)
    defp email(line), do: Map.put(line, :kind, :email)

    test "a business plan line in force makes the segment :plan, otherwise :business_email" do
      both = [
        plan(yearly(~D[2026-03-01], 1_200_000, subscription: "a")),
        email(yearly(~D[2026-03-01], 52_900, subscription: "b"))
      ]

      assert Periods.segment(both, @as_of) == :plan
      assert Periods.segment([email(yearly(~D[2026-03-01], 52_900))], @as_of) == :business_email
      # An expired plan line does not count; only the lines in force on the date.
      assert Periods.segment([plan(yearly(~D[2024-03-01], 1_200_000))], @as_of) ==
               :business_email

      assert Periods.line_segment(plan(yearly(~D[2026-03-01], 1))) == :plan
      assert Periods.line_segment(email(yearly(~D[2026-03-01], 1))) == :business_email
    end

    test "renewal per segment counts the due lines of that segment and sums to the total" do
      lines_by_user = %{
        # A business plan year renewed.
        a: [plan(yearly(~D[2025-03-01], 1_200_000)), plan(yearly(~D[2026-03-01], 1_200_000))],
        # An email-plan year renewed by a business plan: due in the email segment.
        b: [email(yearly(~D[2025-04-01], 52_900)), plan(yearly(~D[2026-04-01], 1_200_000))],
        # An email-plan year not renewed.
        c: [email(yearly(~D[2025-05-01], 52_900))]
      }

      total = Periods.renewal(lines_by_user, @as_of, @renewal_opts)

      by_segment =
        Map.new(Periods.segments(), fn segment ->
          opts = Keyword.put(@renewal_opts, :segment, segment)
          {segment, Periods.renewal(lines_by_user, @as_of, opts)}
        end)

      assert total.client == %{rate: 2 / 3, renewed: 2, due: 3}
      assert by_segment.plan.client == %{rate: 1.0, renewed: 1, due: 1}
      assert by_segment.business_email.client == %{rate: 0.5, renewed: 1, due: 2}

      assert by_segment.plan.revenue.due_acv + by_segment.business_email.revenue.due_acv ==
               total.revenue.due_acv

      assert by_segment.plan.revenue.renewed_acv + by_segment.business_email.revenue.renewed_acv ==
               total.revenue.renewed_acv
    end
  end
end
