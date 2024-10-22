{:ok, _} = Application.ensure_all_started(:ex_machina)
:erlang.system_flag(:backtrace_depth, 20)

ExUnit.configure(exclude: [skip_suite: true])

Mox.defmock(Sanbase.Notifications.MockDiscordClient, for: Sanbase.Notifications.DiscordBehaviour)

Mox.defmock(Sanbase.Notifications.MockEmailClient,
  for: Sanbase.Notifications.EmailClientBehaviour
)

# Set the mock client in the application environment
Application.put_env(:sanbase, :discord_client, Sanbase.Notifications.MockDiscordClient)
Application.put_env(:sanbase, :email_client, Sanbase.Notifications.MockEmailClient)
ExUnit.start()
Faker.start()

Ecto.Adapters.SQL.Sandbox.mode(Sanbase.Repo, :manual)
