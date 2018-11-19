if Code.ensure_loaded?(Prometheus) do
  defmodule SanbaseWeb.Graphql.Prometheus.CounterBackend do
    @behaviour AbsintheMetrics
    use Prometheus

    @query_metric_name :graphql_query_total_calls
    @field_metric_name :graphql_query_field_total_calls

    def field(object, field, args \\ [])

    def field(:query, _field, _args) do
      _ =
        Counter.declare(
          name: @query_metric_name,
          help: "Total calls for a GraphQL API query",
          labels: [:status, :query]
        )
    end

    def field(_object, _field, _args) do
      _ =
        Counter.declare(
          name: @field_metric_name,
          help: "Total calls for a GraphQL API field",
          labels: [:object, :field, :status]
        )
    end

    def instrument(:query, query, {status, _}, _time) do
      Counter.inc(name: @query_metric_name, labels: [status, query])
    end

    def instrument(object, field, {status, _}, _time) do
      Counter.inc(name: @field_metric_name, labels: [object, field, status])
    end
  end
end
