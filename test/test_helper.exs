{:ok, _} = Application.ensure_all_started(:ex_machina)
:erlang.system_flag(:backtrace_depth, 20)

ExUnit.start()
Faker.start()

Ecto.Adapters.SQL.Sandbox.mode(Sanbase.Repo, :manual)
ExUnit.configure(exclude: [historical_balance: true])
