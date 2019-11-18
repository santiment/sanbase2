defmodule Sanbase.Model.Kafka.KafkaLabelRecord do
  use Ecto.Schema
  import Ecto.Changeset

  schema "kafka_label_records" do
    field(:topic, :string)
    field(:sign, :integer, default: 1)
    field(:address, :string)
    field(:blockchain, :string)
    field(:label, :string)
    field(:metadata, :string)
    field(:datetime, :naive_datetime)
  end

  @fields [:sign, :address, :blockchain, :label, :metadata, :datetime]
  def changeset(struct, attrs \\ %{}) do
    struct |> cast(attrs, @fields) |> validate_required(@fields)
  end
end

defmodule Sanbase.ExAdmin.Kafka.KafkaLabelRecord do
  use ExAdmin.Register

  register_resource Sanbase.Model.Kafka.KafkaLabelRecord do
    form label do
      inputs do
        input(label, :topic)
        input(label, :sign)
        input(label, :address)
        input(label, :blockchain)
        input(label, :label)
        input(label, :metadata)
        input(label, :datetime)
      end
    end

    controller do
      before_filter(:send_to_kafka, only: [:create])
    end
  end

  def send_to_kafka(conn, params) do
    {topic, data} = Map.pop(params, :topic)

    data =
      data
      |> List.wrap()
      |> Enum.map(&{"", Jason.encode!(&1)})

    SanExporterEx.Producer.send_data(topic, data)

    {conn, params}
  end
end
