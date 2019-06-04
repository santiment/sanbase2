defmodule SanbaseWeb.Graphql.Clickhouse.GasUsedTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]
  import ExUnit.CaptureLog
  import Sanbase.Factory

  alias Sanbase.Clickhouse.GasUsed

  setup do
    user = insert(:staked_user)
    conn = setup_jwt_auth(build_conn(), user)

    [
      conn: conn,
      slug: "ethereum",
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z"),
      interval: "1d"
    ]
  end

  test "returns data from calculation", context do
    with_mock GasUsed,
      gas_used: fn _, _, _, _ ->
        {:ok,
         [
           %{
             gas_used: 100,
             datetime: from_iso8601!("2019-01-01T00:00:00Z")
           },
           %{
             gas_used: 200,
             datetime: from_iso8601!("2019-01-02T00:00:00Z")
           }
         ]}
      end do
      response = execute_query(context.slug, context)
      result = parse_response(response)

      assert_called(GasUsed.gas_used(context.slug, context.from, context.to, context.interval))

      assert result == [
               %{
                 "gasUsed" => 100,
                 "datetime" => "2019-01-01T00:00:00Z"
               },
               %{
                 "gasUsed" => 200,
                 "datetime" => "2019-01-02T00:00:00Z"
               }
             ]
    end
  end

  test "returns empty array when there is no data", context do
    with_mock GasUsed, gas_used: fn _, _, _, _ -> {:ok, []} end do
      response = execute_query(context.slug, context)
      result = parse_response(response)

      assert_called(GasUsed.gas_used(context.slug, context.from, context.to, context.interval))
      assert result == []
    end
  end

  test "logs warning when calculation errors", context do
    error = "Some error description here"

    with_mock GasUsed,
      gas_used: fn _, _, _, _ -> {:error, error} end do
      assert capture_log(fn ->
               response = execute_query(context.slug, context)
               result = parse_response(response)
               assert result == nil
             end) =~
               graphql_error_msg("Gas Used", context.slug, error)
    end
  end

  test "uses 1d as default interval", context do
    with_mock GasUsed, gas_used: fn _, _, _, _ -> {:ok, []} end do
      query = """
        {
          gasUsed(slug: "#{context.slug}", from: "#{context.from}", to: "#{context.to}"){
            datetime,
            gasUsed
          }
        }
      """

      context.conn
      |> post("/graphql", query_skeleton(query, "gasUsed"))

      assert_called(GasUsed.gas_used(context.slug, context.from, context.to, "1d"))
    end
  end

  test "works only for ethereum", context do
    error = "Currently only ethereum is supported!"

    with_mock GasUsed,
      gas_used: fn _, _, _, _ -> {:error, error} end do
      assert capture_log(fn ->
               response = execute_query("unsupported", context)
               result = parse_response(response)
               assert result == nil
             end) =~
               graphql_error_msg("Gas Used", "unsupported", error)
    end
  end

  describe "deprecated" do
    test "works without a slug, using ethereum as default one", context do
      with_mock GasUsed, gas_used: fn _, _, _, _ -> {:ok, []} end do
        query = """
          {
            gasUsed(from: "#{context.from}", to: "#{context.to}", interval: "#{context.interval}"){
              datetime,
              gasUsed
            }
          }
        """

        context.conn
        |> post("/graphql", query_skeleton(query, "gasUsed"))

        assert_called(GasUsed.gas_used(context.slug, context.from, context.to, "1d"))
      end
    end

    test "has deprecated ethGasUsed", context do
      with_mock GasUsed,
        gas_used: fn _, _, _, _ ->
          {:ok,
           [
             %{
               eth_gas_used: 100,
               datetime: from_iso8601!("2019-01-01T00:00:00Z")
             },
             %{
               eth_gas_used: 200,
               datetime: from_iso8601!("2019-01-02T00:00:00Z")
             }
           ]}
        end do
        query = """
          {
            gasUsed(from: "#{context.from}", to: "#{context.to}", interval: "#{context.interval}"){
              datetime,
              ethGasUsed
            }
          }
        """

        response =
          context.conn
          |> post("/graphql", query_skeleton(query, "gasUsed"))

        result = parse_response(response)

        assert_called(GasUsed.gas_used(context.slug, context.from, context.to, context.interval))

        assert result == [
                 %{
                   "ethGasUsed" => 100,
                   "datetime" => "2019-01-01T00:00:00Z"
                 },
                 %{
                   "ethGasUsed" => 200,
                   "datetime" => "2019-01-02T00:00:00Z"
                 }
               ]
      end
    end
  end

  defp parse_response(response) do
    json_response(response, 200)["data"]["gasUsed"]
  end

  defp execute_query(slug, context) do
    query = gas_used_query(slug, context.from, context.to, context.interval)

    context.conn
    |> post("/graphql", query_skeleton(query, "gasUsed"))
  end

  defp gas_used_query(slug, from, to, interval) do
    """
      {
        gasUsed(slug: "#{slug}", from: "#{from}", to: "#{to}", interval: "#{interval}"){
          datetime,
          gasUsed
        }
      }
    """
  end
end
