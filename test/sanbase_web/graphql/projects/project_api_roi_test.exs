defmodule SanbaseWeb.Graphql.ProjectApiRoiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Model.Ico

  require Sanbase.Mock

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
    |> Ico.changeset(%{project_id: project.id, start_date: DateTime.to_date(dt1)})
    |> Sanbase.Repo.insert!()

    %Ico{}
    |> Ico.changeset(%{
      project_id: project.id,
      start_date: DateTime.to_date(dt2),
      token_eth_ico_price: 5
    })
    |> Sanbase.Repo.insert!()

    %{project: project, datetime: dt1}
  end

  test "fetch project ROI", context do
    response = last_record_before_fixture(context)

    (&Sanbase.Price.last_record_before/2)
    |> Sanbase.Mock.prepare_mock2(response)
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert get_roi(context.conn, context.project) == %{"roiUsd" => "2.5"}
    end)
  end

  test "fetch project ROI2", context do
    response = last_record_before_fixture(context)

    (&Sanbase.Price.last_record_before/2)
    |> Sanbase.Mock.prepare_mock2(response)
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert get_roi(context.conn, context.project) == %{"roiUsd" => "2.5"}
    end)
  end

  defp last_record_before_fixture(%{datetime: dt}) do
    {:ok, %{datetime: dt, price_usd: 5, price_btc: 0.1, marketcap_usd: 500, volume_usd: 200}}
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
