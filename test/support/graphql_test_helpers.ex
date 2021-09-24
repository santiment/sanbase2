defmodule SanbaseWeb.Graphql.TestHelpers do
  import Plug.Conn
  import Phoenix.ConnTest
  import Sanbase.Factory

  alias Sanbase.{Metric, Signal}
  alias Sanbase.Billing.Plan.AccessChecker

  # The default endpoint for testing
  @endpoint SanbaseWeb.Endpoint
  @custom_access_metrics Sanbase.Billing.Plan.CustomAccess.get()
                         |> Enum.filter(&match?({{:metric, _}, _}, &1))
                         |> Enum.map(fn {{_, name}, _} -> name end)

  def v2_restricted_metric_for_plan(position, product, plan_name) do
    all_v2_restricted_metrics_for_plan(product, plan_name)
    |> Stream.cycle()
    |> Enum.at(position)
  end

  def all_v2_restricted_metrics_for_plan(product, plan_name) do
    (Metric.restricted_metrics() -- @custom_access_metrics)
    |> Enum.filter(&AccessChecker.plan_has_access?(plan_name, product, {:metric, &1}))
  end

  def restricted_signal_for_plan(position, product, plan_name) do
    Signal.restricted_signals()
    |> Enum.filter(&AccessChecker.plan_has_access?(plan_name, product, {:signal, &1}))
    |> Stream.cycle()
    |> Enum.at(position)
  end

  def get_free_timeseries_element(position, product, argument)
      when argument in [:metric, :signal] do
    free_timeseries_elements(product, argument)
    |> Enum.to_list()
    |> Stream.cycle()
    |> Enum.at(position)
  end

  defp free_timeseries_elements(product, :metric) do
    Metric.min_plan_map()
    |> Enum.filter(fn
      {_, :free} -> true
      {_, %{^product => :free}} -> true
      _ -> false
    end)
    |> Enum.map(fn {metric, _} -> metric end)
    |> MapSet.new()
    |> MapSet.intersection(MapSet.new(Metric.free_metrics()))
    |> MapSet.intersection(MapSet.new(Metric.available_timeseries_metrics()))
  end

  defp free_timeseries_elements(product, :signal) do
    Signal.min_plan_map()
    |> Enum.filter(fn
      {_, :free} -> true
      {_, %{^product => :free}} -> true
      _ -> false
    end)
    |> Enum.map(fn {signal, _} -> signal end)
    |> MapSet.new()
    |> MapSet.intersection(MapSet.new(Signal.free_signals()))
    |> MapSet.intersection(MapSet.new(Signal.available_timeseries_signals()))
  end

  def from_to(from_days_shift, to_days_shift) do
    from = Timex.shift(Timex.now(), days: -from_days_shift)
    to = Timex.shift(Timex.now(), days: -to_days_shift)
    {from, to}
  end

  def query_skeleton(query, query_name \\ "", variable_defs \\ "", variables \\ "{}") do
    %{
      "operationName" => "#{query_name}",
      "query" => "query #{query_name}#{variable_defs} #{query}",
      "variables" => "#{variables}"
    }
  end

  def mutation_skeleton(mutation, mutation_name \\ "") do
    %{
      "operationName" => "#{mutation_name}",
      "query" => "#{mutation}",
      "variables" => ""
    }
  end

  def setup_jwt_auth(conn, user) do
    device_data = SanbaseWeb.Guardian.device_data(conn)

    {:ok, tokens} =
      SanbaseWeb.Guardian.get_jwt_tokens(user,
        platform: device_data.platform,
        client: device_data.client
      )

    conn
    |> Plug.Test.init_test_session(tokens)
  end

  def setup_apikey_auth(conn, apikey) do
    conn
    |> put_req_header("authorization", "Apikey " <> apikey)
  end

  def setup_basic_auth(conn, user, pass) do
    token = Base.encode64(user <> ":" <> pass)

    conn
    |> put_req_header("authorization", "Basic " <> token)
  end

  def execute_query(conn, query, query_name) do
    conn
    |> post("/graphql", query_skeleton(query, query_name))
    |> json_response(200)
    |> get_in(["data", query_name])
  end

  def execute_query_with_error(conn, query, query_name) do
    conn
    |> post("/graphql", query_skeleton(query, query_name))
    |> json_response(200)
    |> Map.get("errors")
    |> hd()
    |> Map.get("message")
  end

  def execute_mutation(conn, query, query_name) do
    conn
    |> post("/graphql", mutation_skeleton(query))
    |> json_response(200)
    |> get_in(["data", query_name])
  end

  def execute_mutation_with_error(conn, query) do
    conn
    |> post("/graphql", mutation_skeleton(query))
    |> json_response(200)
    |> Map.get("errors")
    |> hd()
    |> Map.get("message")
  end

  def string_list_to_string(list) do
    str = list |> Enum.map(fn elem -> ~s|"#{elem}"| end) |> Enum.join(",")
    "[" <> str <> "]"
  end

  def map_to_args(%{} = map, opts \\ []) do
    map_as_input_object? = Keyword.get(opts, :map_as_input_object, false)

    map = Map.delete(map, :map_as_input_object)

    Enum.map(map, fn
      {k, [%{} | _] = l} ->
        ~s/#{k}: [#{Enum.map(l, &map_to_input_object_str/1) |> Enum.join(",")}]/

      {k, %DateTime{} = dt} ->
        ~s/#{k}: "#{dt |> DateTime.truncate(:second) |> DateTime.to_iso8601()}"/

      {k, m} when is_map(m) ->
        if map_as_input_object? || Map.get(m, :map_as_input_object) do
          m = Map.delete(m, :map_as_input_object)
          ~s/#{k}: #{map_to_input_object_str(m)}/
        else
          ~s/#{k}: '#{Jason.encode!(m)}'/
          |> String.replace(~r|\"|, ~S|\\"|)
          |> String.replace(~r|'|, ~S|"|)
        end

      {k, a} when a in [true, false, nil] ->
        ~s/#{k}: #{inspect(a)}/

      {k, a} when is_atom(a) ->
        ~s/#{k}: #{a |> Atom.to_string() |> String.upcase()}/

      {k, v} ->
        ~s/#{k}: #{inspect(v)}/
    end)
    |> Enum.join(", ")
  end

  def map_to_input_object_str(%{} = map, opts \\ []) do
    "{" <> map_to_args(map, opts) <> "}"
  end

  def graphql_error_msg(metric_name, error) do
    "Can't fetch #{metric_name}, Reason: \"#{error}\""
  end

  def graphql_error_msg(metric_name, slug, error) do
    "Can't fetch #{metric_name} for project with slug #{slug}, Reason: \"#{error}\""
  end

  # Add the missing required selector fields to the selector
  # Some queries require some additional fields in order to work. If these
  # fields are not provided, the query will fail before calling the DB. Such cases
  # are some label metrics where the labels must be provided or some social metrics
  # where the source must be provided.
  # This function should be used only when we do some high-level testing that
  # all the metrics can be executed and return data. In these cases we select
  # random 100-200 metrics and mock the `Sanbase.Metric` module to return data.
  # This ensures that we cover all the possible paths and checks in the resolver
  def extend_selector_with_required_fields(metric, selector) do
    case Sanbase.Metric.required_selectors(metric) do
      {:ok, [_ | _] = required_selectors} ->
        selector_fields = Map.keys(selector)

        # The missing fields are a list of lists. If the list-element contains
        # more than one element, only one of them is required. In this case
        # select one of them at random and fill it.
        missing_required_selector_fields =
          Enum.reject(required_selectors, fn list ->
            Enum.any?(list, &(&1 in selector_fields))
          end)

        Enum.reduce(missing_required_selector_fields, selector, fn list, selector_acc ->
          list |> Enum.random() |> add_missing_selector(selector_acc)
        end)

      _ ->
        # This case covers the case where the metric does not have any required
        # selector fields. It also handles the case where the metric is not supported
        # In case of not-supproted metrics we don't want to break here as we want
        # to test the API behaviour in such cases
        selector
    end
  end

  defp add_missing_selector(:label_fqn, selector),
    do: Map.put(selector, :label_fqn, "santiment/owner->Coinbase:v1")

  defp add_missing_selector(:label_fqns, selector) do
    Map.put(selector, :label_fqns, ["santiment/owner->Coinbase:v1", "santiment/owner->Binance:v1"])
  end

  defp add_missing_selector(:source, selector) do
    source = Enum.random(["twitter", "reddit", "bitcointalk"])
    Map.put(selector, :source, source)
  end

  defp add_missing_selector(:blockchain_address, selector) do
    # Add `map_as_input_object` flag as an implementation detail for the
    # map_to_input_object_str/{1,2} function so this is not encoded as json
    blockchain_address = %{map_as_input_object: true, address: "0x" <> rand_hex_str(38)}
    Map.put(selector, :blockchain_address, blockchain_address)
  end
end
