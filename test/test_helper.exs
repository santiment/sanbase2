{:ok, _} = Application.ensure_all_started(:ex_machina)
:erlang.system_flag(:backtrace_depth, 20)

# anubis_mcp 1.8.0 removed its own `application/0` callback, so the Finch pool
# its HTTP transports default to is no longer started automatically. Only
# Sanbase.MCP.Client (a test-only MCP client) uses such a transport - the
# production side is a server plug and needs no pool - so it is started here.
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
