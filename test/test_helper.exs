{:ok, _} = Application.ensure_all_started(:ex_machina)

ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(Sanbase.Repo, :manual)
Ecto.Adapters.SQL.Sandbox.mode(Sanbase.TimescaleRepo, :manual)

ExUnit.configure(exclude: [timescaledb: true])
Sanbase.Prices.Store.create_db()
