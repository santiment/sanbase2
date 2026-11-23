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

  test "a non-200 response is an error for every id instead of raising" do
    response = %Req.Response{status: 400, body: "<html>Bad Request</html>"}

    Sanbase.Mock.prepare_mock2(&Req.get/2, {:ok, response})
    |> Sanbase.Mock.run_with_mocks(fn ->
      data = MapSet.new([["1"], ["2"]])

      assert %{"1" => {:error, error}, "2" => {:error, error}} =
               MetricshubDataloader.query(:social_documents_by_ids, data, nil)

      assert is_binary(error)
    end)
  end
end
