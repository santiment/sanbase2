defmodule SanbaseWeb.Graphql.TestHelpers do
  import Plug.Conn
  import Phoenix.ConnTest
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
    (Sanbase.Metric.restricted_metrics() -- @custom_access_metrics)
    |> Enum.filter(&AccessChecker.plan_has_access?(plan_name, product, {:metric, &1}))
  end

  def v2_free_timeseries_metric(position, product) do
    free_access_metrics = Sanbase.Metric.free_metrics()
    timeseries_metrics = Sanbase.Metric.available_timeseries_metrics()

    free_metrics_per_plan =
      Sanbase.Metric.min_plan_map()
      |> Enum.filter(fn
        {_, :free} -> true
        %{^product => :free} -> true
        _ -> false
      end)
      |> Enum.map(fn {metric, _} -> metric end)

    MapSet.new(free_metrics_per_plan)
    |> MapSet.intersection(MapSet.new(free_access_metrics))
    |> MapSet.intersection(MapSet.new(timeseries_metrics))
    |> Enum.to_list()
    |> Stream.cycle()
    |> Enum.at(position)
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
    {:ok, token, _claims} = SanbaseWeb.Guardian.encode_and_sign(user, %{salt: user.salt})

    conn
    |> put_req_header("authorization", "Bearer " <> token)
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

  def map_to_input_object_str(%{} = map, opts \\ []) do
    map_as_input_object? = Keyword.get(opts, :map_as_input_object, false)

    str =
      Enum.map(map, fn
        {k, [%{} | _] = l} ->
          ~s/#{k}: [#{Enum.map(l, &map_to_input_object_str/1) |> Enum.join(",")}]/

        {k, %DateTime{} = dt} ->
          ~s/#{k}: "#{dt |> DateTime.truncate(:second) |> DateTime.to_iso8601()}"/

        {k, m} when is_map(m) ->
          if map_as_input_object? do
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

    "{" <> str <> "}"
  end

  def graphql_error_msg(metric_name, error) do
    "Can't fetch #{metric_name}, Reason: \"#{error}\""
  end

  def graphql_error_msg(metric_name, slug, error) do
    "Can't fetch #{metric_name} for project with slug #{slug}, Reason: \"#{error}\""
  end
end
