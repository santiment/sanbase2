IO.puts("Running test seeds")

IO.puts("Populating the Metric Registry...")

{:ok, metrics, summary} = Sanbase.Metric.Registry.Populate.run()

IO.puts(
  "Finished populating the Metric Registry. Inserted #{length(metrics)} metrics. Summary: #{inspect(summary)}"
)
