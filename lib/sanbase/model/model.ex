defmodule Sanbase.Model do
  import Ecto.Query, warn: false
  alias Sanbase.Repo

  alias Sanbase.Model.Project
  alias Sanbase.Model.Ico
  alias Sanbase.Model.Currency
  alias Sanbase.Model.Infrastructure

  def get_currency(currency_code) do
    Repo.get_by(Currency, code: currency_code)
  end

  def insert_currency!(currency_code) do
    %Currency{}
    |> Currency.changeset(%{code: currency_code})
    |> Repo.insert!()
  end

  def get_or_insert_currency(currency_code) do
    {:ok, currency} = Repo.transaction(fn ->
      get_currency(currency_code)
      |> case do
        nil -> insert_currency!(currency_code)
        currency -> currency
      end
    end)

    currency
  end

  def get_infrastructure(infrastructure_code) do
    Repo.get_by(Infrastructure, code: infrastructure_code)
  end

  def insert_infrastructure!(infrastructure_code) do
    %Infrastructure{}
    |> Infrastructure.changeset(%{code: infrastructure_code})
    |> Repo.insert!()
  end

  def get_or_insert_infrastructure(infrastructure_code) do
    {:ok, infrastructure} = Repo.transaction(fn ->
      get_infrastructure(infrastructure_code)
      |> case do
        nil -> insert_infrastructure!(infrastructure_code)
        infrastructure -> infrastructure
      end
    end)

    infrastructure
  end
end
