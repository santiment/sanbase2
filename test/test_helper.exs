{:ok, _} = Application.ensure_all_started(:ex_machina)
:erlang.system_flag(:backtrace_depth, 20)

ExUnit.configure(
  exclude: [skip_suite: true],
  max_cases: System.schedulers_online() * 2
)

# Set test environment variable for OpenAI to prevent runtime errors
System.put_env("OPENAI_API_KEY", "test-key-for-testing")

Mox.defmock(Sanbase.Notifications.MockDiscordClient, for: Sanbase.Notifications.DiscordBehaviour)

Mox.defmock(Sanbase.Notifications.MockEmailClient,
  for: Sanbase.Notifications.EmailClientBehaviour
)

Mox.defmock(Sanbase.Email.MockMailjetApi, for: Sanbase.Email.MailjetApiBehaviour)

# Mock for OpenAI Client
Mox.defmock(Sanbase.AI.MockOpenAIClient, for: Sanbase.AI.OpenAIClientBehaviour)

# Set the mock clients in the application environment
Application.put_env(:sanbase, :discord_client, Sanbase.Notifications.MockDiscordClient)
Application.put_env(:sanbase, :mailjet_api, Sanbase.Email.MockMailjetApi)
Application.put_env(:sanbase, :openai_client, Sanbase.AI.MockOpenAIClient)

ExUnit.start()
Faker.start()

Ecto.Adapters.SQL.Sandbox.mode(Sanbase.Repo, :manual)

# Seed the privacy-masking cache with the legacy 1..10 range so existing tests
# that `insert(:user, id: 1)` and then assert protection still work without
# touching the DB. Individual tests that exercise the DB→cache path call
# `Sanbase.Accounts.ProtectedUser.refresh/0` and restore this seed in on_exit.
:persistent_term.put(
  Sanbase.Accounts.ProtectedUser.cache_key(),
  {MapSet.new(1..10), System.monotonic_time(:second)}
)
