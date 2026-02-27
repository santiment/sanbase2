defmodule Mix.Tasks.LoadTest.Setup do
  use Mix.Task

  @shortdoc "Seed test users with API keys and Business Pro subscriptions for load testing"

  @moduledoc """
  Creates load test users with API keys and Business Pro subscriptions,
  then writes the API keys to a JSON file for k6.

      mix load_test.setup --users 20

  Options:
    --users  Number of users to create (default: 20)

  Each user gets:
    - An email like `loadtest_N@sanload.test`
    - One API key
    - A Business Pro monthly subscription (plan_id 107)

  The API keys are written to `load_test/data/apikeys.json`.

  This task is idempotent — re-running it will reuse existing users and
  generate fresh API keys.
  """

  @business_pro_monthly_plan_id 107

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)
    count = Keyword.get(opts, :users, 20)

    Mix.shell().info("Creating #{count} load test users with Business Pro subscriptions...")

    apikeys =
      Enum.map(1..count, fn i ->
        email = "loadtest_#{i}@sanload.test"

        {:ok, user} =
          Sanbase.Accounts.User.find_or_insert_by(:email, email, %{
            username: "loadtest_#{i}",
            privacy_policy_accepted: true
          })

        ensure_subscription(user)

        {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)

        Mix.shell().info("  User #{i}: #{email} -> apikey + Business Pro")
        apikey
      end)

    output_path = Path.join([File.cwd!(), "load_test", "data", "apikeys.json"])
    File.write!(output_path, Jason.encode!(apikeys, pretty: true))

    Mix.shell().info("\nDone! #{count} API keys written to #{output_path}")
  end

  @sanapi_product_id 1

  defp ensure_subscription(user) do
    case Sanbase.Billing.Subscription.current_subscription(user, @sanapi_product_id) do
      nil ->
        Sanbase.Billing.Subscription.create(%{
          user_id: user.id,
          plan_id: @business_pro_monthly_plan_id,
          status: "active",
          current_period_end: Timex.shift(Timex.now(), years: 1),
          type: :fiat
        })

      _subscription ->
        :ok
    end
  end

  defp parse_args(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [users: :integer])
    opts
  end
end
