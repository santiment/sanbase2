defmodule Sanbase.Billing.AccessMatrixCharacterizationTest do
  @moduledoc ~s"""
  Pins today's plan-dependent access and quota behavior against a committed
  fixture.

  This is a characterization test, not a correctness test. It makes no claim
  that any recorded answer is *right* - only that it has not *changed*. Its
  purpose is the backward-compatibility contract in
  `docs/composable-api-plans-handover.md` §7.1: while composable/bundle plans
  are built, every existing plan must keep behaving exactly as it does today.

  ## When this test fails

  A failure means a plan-dependent answer moved. Either the change is
  unintentional - fix the code - or it is deliberate, in which case regenerate
  the fixture and make the diff a reviewed part of the pull request:

      UPDATE_ACCESS_MATRIX=1 mix test test/sanbase/billing/access_matrix_characterization_test.exs

  Never regenerate to make a red build green without reading the diff. The diff
  *is* the review artifact.
  """

  use Sanbase.DataCase, async: false

  alias Sanbase.Billing.AccessMatrix

  @fixture_path "test/fixtures/billing/access_matrix.json"
  @custom_plan_name "CUSTOM_CHARACTERIZATION"

  setup context do
    # The seeded plans use hardcoded ids, so let the sequence start above them.
    Sanbase.Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9001")
    {:ok, _plan} = create_custom_plan(context)
    :ok
  end

  test "plan access and quota matrix is unchanged" do
    actual =
      AccessMatrix.build(plan_names: AccessMatrix.standard_plan_names() ++ [@custom_plan_name])

    if System.get_env("UPDATE_ACCESS_MATRIX") do
      write_fixture(actual)

      flunk("""
      Fixture regenerated at #{@fixture_path}.

      Review the diff and commit it if the change is intended, then re-run
      without UPDATE_ACCESS_MATRIX=1.
      """)
    end

    expected = read_fixture()

    for {product, plans} <- expected, {plan_name, snapshot} <- plans do
      actual_snapshot = get_in(actual, [product, plan_name])

      assert actual_snapshot == snapshot,
             failure_message(
               "Plan-dependent behavior changed for product=#{product} plan=#{plan_name}.",
               snapshot,
               actual_snapshot
             )
    end

    # Catches anything the per-plan loop cannot: a plan added to or removed from
    # AccessMatrix.standard_plan_names/0 shows up here as an (absent) entry.
    assert actual == expected,
           failure_message("The access matrix no longer matches the fixture.", expected, actual)
  end

  # The failure explains the whole workflow inline. Nobody should have to
  # remember the regeneration flag or go read the moduledoc to act on a red
  # build.
  defp failure_message(headline, expected, actual) do
    """
    #{headline}

    #{changed_values(expected, actual)}

    WHAT NOW?

    1. If this change was NOT intended, you have found a regression - fix the
       code. That is what this test is for: every existing plan must keep
       behaving exactly as it did.

    2. If it WAS intended, regenerate the fixture and commit the diff as part of
       your PR:

         UPDATE_ACCESS_MATRIX=1 mix test #{Path.relative_to_cwd(__ENV__.file)}
         git diff #{@fixture_path}

       That diff is the review artifact - it shows the full behavioral
       consequence of your change in one place. Never regenerate just to turn the
       build green without reading it.
    """
  end

  @max_reported_changes 20

  # Reports changed leaves as `path: old -> new` so the failure diagnoses itself
  # without a regenerate-and-diff round trip.
  defp changed_values(expected, actual) do
    flat_expected = flatten(expected)
    flat_actual = flatten(actual)

    changes =
      MapSet.union(MapSet.new(Map.keys(flat_expected)), MapSet.new(Map.keys(flat_actual)))
      |> Enum.sort()
      |> Enum.reject(&(fetch(flat_expected, &1) == fetch(flat_actual, &1)))

    reported =
      changes
      |> Enum.take(@max_reported_changes)
      |> Enum.map_join("\n", fn path ->
        "  #{path}: #{render(fetch(flat_expected, path))} -> #{render(fetch(flat_actual, path))}"
      end)

    case length(changes) - @max_reported_changes do
      extra when extra > 0 -> reported <> "\n  ...and #{extra} more"
      _ -> reported
    end
  end

  defp fetch(map, path), do: Map.get(map, path, :__absent__)

  defp render(:__absent__), do: "(absent)"
  defp render(value), do: inspect(value)

  defp flatten(value, prefix \\ [], acc \\ %{})

  defp flatten(%{} = map, prefix, acc) do
    Enum.reduce(map, acc, fn {key, value}, acc ->
      flatten(value, prefix ++ [to_string(key)], acc)
    end)
  end

  defp flatten(value, prefix, acc), do: Map.put(acc, Enum.join(prefix, "."), value)

  defp read_fixture do
    case File.read(@fixture_path) do
      {:ok, contents} ->
        Jason.decode!(contents)

      {:error, :enoent} ->
        flunk("""
        Missing fixture #{@fixture_path}.

        Generate it from the current code with:
          UPDATE_ACCESS_MATRIX=1 mix test #{__ENV__.file |> Path.relative_to_cwd()}
        """)
    end
  end

  defp write_fixture(matrix) do
    File.mkdir_p!(Path.dirname(@fixture_path))
    File.write!(@fixture_path, Jason.encode!(matrix, pretty: true) <> "\n")
  end

  # A custom plan whose restrictions are fully specified here, so the CUSTOM_*
  # code path is pinned by the fixture and not just the standard ladder. Values
  # are arbitrary but must stay stable - changing them changes the fixture.
  defp create_custom_plan(context) do
    Sanbase.Billing.Plan.create_custom_api_plan(%{
      id: 9100,
      name: @custom_plan_name,
      product_id: context.product_api.id,
      stripe_id: context.product_api.stripe_id,
      amount: 42_000,
      currency: "USD",
      interval: "month",
      restrictions: %{
        restricted_access_as_plan: "PRO",
        api_call_limits: %{"minute" => 500, "hour" => 50_000, "month" => 1_500_000},
        historical_data_in_days: 730,
        realtime_data_cut_off_in_days: 0,
        metric_access: %{
          "accessible" => ["price_usd", "active_addresses_24h"],
          "accessible_patterns" => ["^social_"],
          "not_accessible" => [],
          "not_accessible_patterns" => ["mvrv_"]
        },
        query_access: %{
          "accessible" => "all",
          "accessible_patterns" => [],
          "not_accessible" => ["history_price"],
          "not_accessible_patterns" => []
        },
        signal_access: %{
          "accessible" => "all",
          "accessible_patterns" => [],
          "not_accessible" => [],
          "not_accessible_patterns" => []
        }
      }
    })
  end
end
