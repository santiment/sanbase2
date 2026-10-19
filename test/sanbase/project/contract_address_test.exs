defmodule Sanbase.Project.ContractAddressTest do
  use Sanbase.DataCase, async: true

  import ExUnit.CaptureLog
  import Sanbase.Factory

  alias Sanbase.Project
  alias Sanbase.Project.ContractAddress

  defp contracts(project) do
    Project.by_id(project.id, preload: [:contract_addresses]).contract_addresses
    |> Map.new(&{&1.address, &1})
  end

  test "add_contract inserts a new contract" do
    project = insert(:random_project, contract_addresses: [])

    {:ok, _} =
      ContractAddress.add_contract(project, %{address: "0x1", label: "main", decimals: 18})

    assert %{"0x1" => %{label: "main", decimals: 18}} = contracts(project)
  end

  test "add_contract updates the label of an existing non-main contract" do
    project =
      insert(:random_project, contract_addresses: [build(:contract_address, address: "0x1")])

    {:ok, _} = ContractAddress.add_contract(project, %{address: "0x1", label: "old_contract"})

    assert %{"0x1" => %{label: "old_contract"}} = contracts(project)
  end

  test "add_contract does not remove the main label" do
    project =
      insert(:random_project,
        contract_addresses: [build(:contract_address, address: "0x1", label: "main")]
      )

    {:ok, _} = ContractAddress.add_contract(project, %{address: "0x1", label: nil, decimals: 6})
    assert %{"0x1" => %{label: "main", decimals: 6}} = contracts(project)

    # The returned contract is the stored one, not the input
    assert {:ok, %ContractAddress{label: "main", decimals: 6}} =
             ContractAddress.add_contract(project, %{address: "0x1", label: "other"})

    assert %{"0x1" => %{label: "main", decimals: 6}} = contracts(project)
  end

  test "add_contract does not remove decimals when given nil decimals" do
    project =
      insert(:random_project,
        contract_addresses: [build(:contract_address, address: "0x1", decimals: 8)]
      )

    {:ok, _} = ContractAddress.add_contract(project, %{address: "0x1", decimals: nil})
    assert %{"0x1" => %{decimals: 8}} = contracts(project)

    {:ok, _} = ContractAddress.add_contract(project, %{address: "0x1", decimals: 18})
    assert %{"0x1" => %{decimals: 18}} = contracts(project)
  end

  test "add_contract keeps the fields that are not given" do
    project =
      insert(:random_project,
        contract_addresses: [
          build(:contract_address,
            address: "0x1",
            label: "old_contract",
            decimals: 8,
            description: "Manually set"
          )
        ]
      )

    {:ok, _} = ContractAddress.add_contract(project, %{address: "0x1"})

    assert %{"0x1" => %{label: "old_contract", decimals: 8, description: "Manually set"}} =
             contracts(project)

    # Explicitly given nil values are still applied
    {:ok, _} = ContractAddress.add_contract(project, %{address: "0x1", description: nil})

    assert %{"0x1" => %{label: "old_contract", decimals: 8, description: nil}} =
             contracts(project)
  end

  test "add_contract does not move the main label to another contract" do
    project =
      insert(:random_project,
        contract_addresses: [
          build(:contract_address, address: "0x1", label: "main"),
          build(:contract_address, address: "0x2", label: "old_contract")
        ]
      )

    log =
      capture_log(fn ->
        # Existing contract keeps its label
        {:ok, _} = ContractAddress.add_contract(project, %{address: "0x2", label: "main"})
        # New contract is inserted without a label
        {:ok, _} = ContractAddress.add_contract(project, %{address: "0x3", label: "main"})
      end)

    assert log =~ "Not labeling 0x2 as main"
    assert log =~ "Not labeling 0x3 as main"

    assert %{
             "0x1" => %{label: "main"},
             "0x2" => %{label: "old_contract"},
             "0x3" => %{label: nil}
           } = contracts(project)
  end
end
