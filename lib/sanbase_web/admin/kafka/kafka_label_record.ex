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

  @fields [:topic, :sign, :address, :blockchain, :label, :metadata, :datetime]
  def changeset(struct, attrs \\ %{}) do
    struct |> cast(attrs, @fields) |> validate_required(@fields)
  end
end

defmodule Sanbase.ExAdmin.Kafka.KafkaLabelRecord do
  use ExAdmin.Register
  require Sanbase.Utils.Config, as: Config
  @producer Config.module_get(Sanbase.KafkaExporter, :producer)
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

  def send_to_kafka(conn, %{kafka_label_record: kafka_label_record} = params) do
    {topic, data} =
      Map.pop(kafka_label_record, :topic)
      |> IO.inspect(label: "45", limit: :infinity)

    case String.contains?(topic, "label") do
      true ->
        data =
          data
          |> List.wrap()
          |> Enum.map(&{"", Jason.encode!(&1)})

        @producer.send_data(topic, data)

        {conn, params}

      false ->
        {Phoenix.Controller.put_flash(
           conn,
           :error,
           "The topic must contain 'label' in its name."
         ), %{params | kafka_label_record: %{}}}
    end
  end
end
