{:ok, _} = Application.ensure_all_started(:ex_machina)
:erlang.system_flag(:backtrace_depth, 20)

{:ok, _} = Finch.start_link(name: Anubis.Finch, pools: %{default: [size: 15]})

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

# Nothing listens on port 1. Without this the agent base URL falls back to the dev
# default (127.0.0.1:2024) whenever a test has not set one, and a runner's request task
# that outlives its test (it is unlinked) would create threads on a developer's LIVE
# agent server. Tests that need a server point base_url at their own fake one.
Application.put_env(
  :sanbase,
  Sanbase.DeepResearch,
  Keyword.put(
    Application.get_env(:sanbase, Sanbase.DeepResearch, []),
    :base_url,
    "http://127.0.0.1:1"
  )
)
