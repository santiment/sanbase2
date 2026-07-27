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
      assert get_in(actual, [product, plan_name]) == snapshot,
             "access matrix changed for product=#{product} plan=#{plan_name}"
    end

    # Asserted after the per-plan comparison so that a changed answer produces a
    # targeted failure message rather than one giant map diff.
    assert actual == expected
  end

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
