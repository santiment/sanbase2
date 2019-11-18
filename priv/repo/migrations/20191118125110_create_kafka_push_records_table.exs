defmodule Sanbase.Repo.Migrations.CreateKafkaPushRecordsTable do
  use Ecto.Migration

  def change do
    create table(:kafka_label_records) do
      add(:topic, :string)
      add(:sign, :integer)
      add(:address, :string)
      add(:blockchain, :string)
      add(:label, :string)
      add(:metadata, :string)
      add(:datetime, :naive_datetime)
    end
  end
end
