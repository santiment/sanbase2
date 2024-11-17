{:ok, _} = Application.ensure_all_started(:ex_machina)
:erlang.system_flag(:backtrace_depth, 20)

ExUnit.configure(exclude: [skip_suite: true])

Mox.defmock(Sanbase.Notifications.MockDiscordClient, for: Sanbase.Notifications.DiscordBehaviour)

Mox.defmock(Sanbase.Notifications.MockEmailClient,
  for: Sanbase.Notifications.EmailClientBehaviour
)

Mox.defmock(Sanbase.Email.MockMailjetApi, for: Sanbase.Email.MailjetApiBehaviour)

# Set the mock clients in the application environment
Application.put_env(:sanbase, :discord_client, Sanbase.Notifications.MockDiscordClient)
Application.put_env(:sanbase, :email_client, Sanbase.Notifications.MockEmailClient)
Application.put_env(:sanbase, :mailjet_api, Sanbase.Email.MockMailjetApi)
ExUnit.start()
Faker.start()

Ecto.Adapters.SQL.Sandbox.mode(Sanbase.Repo, :manual)
