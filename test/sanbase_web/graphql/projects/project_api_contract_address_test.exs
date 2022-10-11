defmodule SanbaseWeb.Graphql.ProjectApiContractAddressTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    project1 =
      insert(:random_project,
        contract_addresses: [build(:contract_address), build(:contract_address)]
      )

    project2 = insert(:random_project, contract_addresses: [build(:contract_address)])
    project3 = insert(:random_project, contract_addresses: [])

    %{project1: project1, project2: project2, project3: project3}
  end

  test "get contract addresses", context do
    %{conn: conn, project1: p1, project2: p2, project3: p3} = context

    %{
      "data" => %{
        "allProjects" => result
      }
    } = get_projects_contract_addresses(conn)

    sorter = fn list ->
      list
      |> Enum.sort_by(& &1["slug"])
      |> Enum.map(fn project ->
        contracts = project["contractAddresses"] |> Enum.sort_by(& &1["address"])

        Map.put(project, "contractAddresses", contracts)
      end)
    end

    result = sorter.(result)

    expected_result =
      Enum.map([p1, p2, p3], fn project ->
        %{
          "slug" => project.slug,
          "contractAddresses" =>
            Enum.map(project.contract_addresses, fn contract ->
              %{
                "address" => contract.address,
                "decimals" => contract.decimals,
                "label" => contract.label,
                "description" => contract.description
              }
            end)
        }
      end)
      |> sorter.()

    assert result == expected_result
  end

  defp get_projects_contract_addresses(conn) do
    query = """
    {
      allProjects{
        slug
        contractAddresses {
          address
          decimals
          label
          description
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "projectBySlug"))
    |> json_response(200)
  end
end
