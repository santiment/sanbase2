defmodule Sanbase.Github.EtherbiApiTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  import Mockery

  test "fetch in transactions and store them", context do
    transactions = [
      {1514765134, 400000000000000000000, "0xfe9e8709d3215310075d67e3ed32a380ccf451c8", "SAN"},
      {1514765415, 200000000000000000000, "0xfe9e8709d3215310075d67e3ed32a380ccf451c8", "SAN"}
    ]

    mock HTTPoison, :get,
        {:ok, %HTTPoison.Response{
          status_code: 200,
          body: Poison.encode!(transactions)
        }}

      address = "0xfe9e8709d3215310075d67e3ed32a380ccf451c8"
  end
end
