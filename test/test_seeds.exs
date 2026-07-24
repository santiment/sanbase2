IO.puts("Running test seeds")

IO.puts("Populating the Metric Registry...")

{:ok, metrics, summary} = Sanbase.Metric.Registry.Populate.run()

IO.puts(
  "Finished populating the Metric Registry. Inserted #{length(metrics)} metrics. Summary: #{inspect(summary)}"
)

IO.puts("Seeding metric vocabulary tags...")

:ok = Sanbase.Metric.Tag.seed_vocabulary_tags()
