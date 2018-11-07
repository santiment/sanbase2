defmodule Sanbase.Repo.Migrations.CreateExchangeAddresses do
  use Ecto.Migration

  def up do
    execute("CREATE TABLE exchange_addresses (LIKE exchange_eth_addresses INCLUDING ALL)")
    execute("CREATE SEQUENCE exchange_addresses_id_seq OWNED BY exchange_addresses.id")

    execute(
      "SELECT setval('exchange_addresses_id_seq', (SELECT MAX(id) FROM exchange_eth_addresses))"
    )

    execute(
      "ALTER TABLE exchange_addresses ALTER id SET DEFAULT nextval('exchange_addresses_id_seq'::regclass)"
    )

    execute("INSERT INTO exchange_addresses SELECT * FROM exchange_eth_addresses")
  end

  def down do
    drop(table(:exchange_addresses))
  end
end
