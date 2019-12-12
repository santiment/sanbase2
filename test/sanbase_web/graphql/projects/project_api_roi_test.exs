defmodule SanbaseWeb.Graphql.ProjectApiRoiTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Model.Ico

  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    insert(:project, %{slug: "ethereum", ticker: "ETH"})

    dt1 = ~U[2017-08-19 00:00:00Z]
    dt2 = ~U[2017-10-17 00:00:00Z]

    project = insert(:random_project)

    insert(:latest_cmc_data, %{
      coinmarketcap_id: project.slug,
      price_usd: 50,
      available_supply: 500
    })

    %Ico{}
    |> Ico.changeset(%{project_id: project.id, token_usd_ico_price: 10, tokens_sold_at_ico: 100})
    |> Sanbase.Repo.insert!()

    %Ico{}
    |> Ico.changeset(%{project_id: project.id, start_date: dt1 |> DateTime.to_date()})
    |> Sanbase.Repo.insert!()

    %Ico{}
    |> Ico.changeset(%{
      project_id: project.id,
      start_date: dt2 |> DateTime.to_date(),
      token_eth_ico_price: 5
    })
    |> Sanbase.Repo.insert!()

    %{project: project, datetime1: dt1, datetime2: dt2}
  end

  test "fetch project ROI", context do
    with_mock Sanbase.Price,
      last_record_before: fn _, _ ->
        {:ok,
         %{
           datetime: context.datetime1,
           price_usd: 5,
           price_btc: 0.1,
           marketcap_usd: 500,
           volume_usd: 200
         }}
      end do
      assert get_roi(context.conn, context.project) == %{"roiUsd" => "2.5"}
    end
  end

  def get_roi(conn, project) do
    query = """
    {
      projectBySlug(slug: "#{project.slug}") {
        roiUsd
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "projectBySlug"])
  end
end
