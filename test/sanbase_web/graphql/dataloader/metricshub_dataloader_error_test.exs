defmodule SanbaseWeb.Graphql.MetricshubDataloaderErrorTest do
  use Sanbase.DataCase, async: false

  alias SanbaseWeb.Graphql.MetricshubDataloader

  test "a failed social documents fetch is an error for every id instead of raising" do
    error = %Req.TransportError{reason: :closed}

    Sanbase.Mock.prepare_mock2(&Req.get/2, {:error, error})
    |> Sanbase.Mock.run_with_mocks(fn ->
      data = MapSet.new([["1", "2"], ["3"]])

      assert MetricshubDataloader.query(:social_documents_by_ids, data, nil) == %{
               "1" => {:error, error},
               "2" => {:error, error},
               "3" => {:error, error}
             }
    end)
  end
end
