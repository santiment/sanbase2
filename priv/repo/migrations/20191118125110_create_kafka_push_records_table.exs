defmodule Sanbase.Repo.Migrations.CreateKafkaPushRecordsTable do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:kafka_label_records) do
      add(:topic, :string, null: false)
      add(:sign, :integer, null: false)
      add(:address, :string, null: false)
      add(:blockchain, :string, null: false)
      add(:label, :string, null: false)
      add(:metadata, :string)
      add(:datetime, :naive_datetime, null: false)
    end
  end
end
