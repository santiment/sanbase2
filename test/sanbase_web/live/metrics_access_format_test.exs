defmodule SanbaseWeb.MetricsAccessFormatTest do
  use ExUnit.Case, async: true

  import SanbaseWeb.MetricsAccessFormat

  @today ~D[2026-11-26]

  describe "history/3" do
    test "all history" do
      assert history(nil, :relative, @today) == "All history"
      assert history(nil, :exact, @today) == "All history"
    end

    test "relative" do
      assert history(730, :relative, @today) == "Last 2 years"
      assert history(365, :relative, @today) == "Last year"
      assert history(1095, :relative, @today) == "Last 3 years"
      assert history(90, :relative, @today) == "Last 90 days"
      assert history(400, :relative, @today) == "Last 400 days"
    end

    test "exact" do
      assert history(730, :exact, @today) == "Since 2024-11-26"
    end
  end

  describe "delay/3" do
    test "no delay" do
      assert delay(nil, :relative, @today) == "No delay"
      assert delay(nil, :exact, @today) == "No delay"
    end

    test "relative and exact" do
      assert delay(30, :relative, @today) == "30-day delay"
      assert delay(1, :relative, @today) == "1-day delay"
      assert delay(30, :exact, @today) == "Until 2026-10-27"
    end
  end

  describe "history_code/3" do
    test "all history" do
      assert history_code(nil, :relative, @today) == "All"
      assert history_code(nil, :exact, @today) == "All"
    end

    test "relative: years when a whole number of years, else days" do
      assert history_code(365, :relative, @today) == "1y"
      assert history_code(730, :relative, @today) == "2y"
      assert history_code(90, :relative, @today) == "90d"
      assert history_code(400, :relative, @today) == "400d"
    end

    test "exact: month and year, short enough for the bar's width" do
      assert history_code(730, :exact, @today) == "since Nov '24"
      assert history_code(365, :exact, @today) == "since Nov '25"
      assert history_code(90, :exact, @today) == "since Aug '26"
    end
  end

  describe "delay_code/3" do
    test "a duration in both modes; no delay has no code" do
      assert delay_code(30, :relative, @today) == "30d"
      assert delay_code(30, :exact, @today) == "30d"
      assert delay_code(nil, :relative, @today) == nil
    end
  end

  describe "label/3, the full text of an access value" do
    test "windows" do
      assert label({:window, nil, nil}, :relative, @today) == "All history · No delay"
      assert label({:window, 365, 30}, :relative, @today) == "Last year · 30-day delay"
      assert label({:window, 730, nil}, :relative, @today) == "Last 2 years · No delay"

      assert label({:window, 730, 30}, :exact, @today) ==
               "Since 2024-11-26 · Until 2026-10-27"
    end

    test "locked" do
      assert label({:locked, "sanbase_max"}, :relative, @today) == "Requires Sanbase Max"
      # No listed plan unlocks it: shown as plainly locked, no plan named.
      assert label({:locked, nil}, :exact, @today) == "Locked"
    end
  end

  describe "code_parts/3, the two parts under the halves of a bar" do
    test "history left, delay right (an em dash for no delay); Full and Locked span both" do
      assert code_parts({:window, nil, nil}, :relative, @today) == :full
      assert code_parts({:window, 730, nil}, :relative, @today) == {"2y", "—"}
      assert code_parts({:window, 365, 30}, :relative, @today) == {"1y", "30d"}
      # "All" keeps a lone "30d" from reading as 30 days of history.
      assert code_parts({:window, nil, 30}, :relative, @today) == {"All", "30d"}
      assert code_parts({:locked, "business_max"}, :relative, @today) == :locked
      assert code_parts({:locked, nil}, :relative, @today) == :locked
    end

    test "exact dates shorten the history to month and year; the delay stays a duration" do
      assert code_parts({:window, 730, 30}, :exact, @today) == {"since Nov '24", "30d"}
      assert code_parts({:window, 730, nil}, :exact, @today) == {"since Nov '24", "—"}
      assert code_parts({:window, nil, nil}, :exact, @today) == :full
    end
  end

  describe "code/3, the parts as one string" do
    test "joined with a middle dot" do
      assert code({:window, nil, nil}, :relative, @today) == "Full"
      assert code({:window, 730, nil}, :relative, @today) == "2y · —"
      assert code({:window, 365, 30}, :relative, @today) == "1y · 30d"
      assert code({:window, nil, 30}, :relative, @today) == "All · 30d"
      assert code({:window, 730, 30}, :exact, @today) == "since Nov '24 · 30d"
      assert code({:locked, nil}, :relative, @today) == "Locked"
    end
  end

  describe "access_note/1, the web app vs API note" do
    @lead "Sanbase plans are built for the web app. Through the API, Sanbase Pro gives " <>
            "only limited access: "
    @tail ", so it isn't suited for API use."
    @api "Business plans are built for the API and also give access to the Sanbase web app."

    defp note(pro_api, pro_calls \\ 5_000),
      do: access_note(%{pro_api: pro_api, pro_calls: pro_calls, business_calls: 600_000})

    test "today's limits name all three" do
      assert note({365, 30}) == %{
               web_app:
                 @lead <> "a shorter history, delayed data and a low API call allowance" <> @tail,
               api: @api
             }
    end

    test "only the limits that apply are named" do
      assert note({365, nil}).web_app ==
               @lead <> "a shorter history and a low API call allowance" <> @tail

      assert note({nil, 30}).web_app ==
               @lead <> "delayed data and a low API call allowance" <> @tail

      # As many calls as Business Pro: the window limits alone.
      assert note({365, 30}, 600_000).web_app ==
               @lead <> "a shorter history and delayed data" <> @tail

      assert note({nil, 30}, 600_000).web_app == @lead <> "delayed data" <> @tail
      assert note({nil, nil}).web_app == @lead <> "a low API call allowance" <> @tail
    end

    test "with no limit at all, the Sanbase Pro sentence is left out" do
      assert note({nil, nil}, 600_000).web_app == "Sanbase plans are built for the web app."
    end
  end

  describe "locked/1" do
    test "plan labels come from plans/0" do
      assert locked("sanbase_max") == "Requires Sanbase Max"
      assert locked("business_pro") == "Requires Business Pro"
    end

    test "nil (no listed plan unlocks it) is plainly locked" do
      assert locked(nil) == "Locked"
    end

    test "unknown plan key raises" do
      assert_raise ArgumentError, fn -> locked("bogus") end
    end
  end
end
