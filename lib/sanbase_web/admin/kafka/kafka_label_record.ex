defmodule Sanbase.Model.Kafka.KafkaLabelRecord do
  use Ecto.Schema
  import Ecto.Changeset

  schema "kafka_label_records" do
    field(:topic, :string)
    field(:sign, :integer)
    field(:address, :string)
    field(:blockchain, :string)
    field(:label, :string)
    field(:metadata, :string)
    field(:datetime, :naive_datetime)
  end

  @fields [:topic, :sign, :address, :blockchain, :label, :metadata, :datetime]
  @required_fields @fields -- [:metadata]

  def changeset(struct, attrs \\ %{}) do
    struct |> cast(attrs, @fields) |> validate_required(@required_fields)
  end
end

defmodule Sanbase.ExAdmin.Kafka.KafkaLabelRecord do
  use ExAdmin.Register
  require Sanbase.Utils.Config, as: Config
  @producer Config.module_get(Sanbase.KafkaExporter, :producer)

  register_resource Sanbase.Model.Kafka.KafkaLabelRecord do
    form label do
      inputs do
        content do
          raw("CSV Format: topic, sign, address, blockchain, label, metadata, datetime")
        end

        input(label, :csv, type: :text, label: "Paste CSV")
      end
    end

    controller do
      before_filter(:process_csv, only: [:create, :update])
    end
  end

  def process_csv(conn, %{kafka_label_record: %{csv: csv}} = params) do
    data =
      csv
      |> String.replace("\r", "")
      |> CSVLixir.Reader.read()
      |> Enum.map(fn list -> Enum.map(list, &String.trim/1) end)
      |> Enum.reject(fn x -> x == [] end)

    topics = Enum.map(data, fn [topic | _] -> topic end)
    datetimes = Enum.map(data, fn list -> List.last(list) end)

    all_present? =
      Enum.reduce(data, true, fn [topic, sign, addr, chain, label, _, dt], acc ->
        acc and topic != "" and sign != "" and addr != "" and chain != "" and label != "" and
          dt != ""
      end)

    Enum.map(datetimes, fn dt ->
      {dt, DateTime.from_iso8601(dt)}
    end)

    cond do
      not all_present? ->
        {Phoenix.Controller.put_flash(
           conn,
           :error,
           "All fields except metadata are mandatory."
         ), %{params | kafka_label_record: %{}}}

      Enum.any?(datetimes, &match?({:error, _}, DateTime.from_iso8601(&1))) ->
        {Phoenix.Controller.put_flash(
           conn,
           :error,
           "All datetimes must be valid ISO8601 string formatted datetimes."
         ), %{params | kafka_label_record: %{}}}

      not Enum.all?(topics, &String.contains?(&1, "label")) ->
        {Phoenix.Controller.put_flash(
           conn,
           :error,
           "Every topic must contain 'label' in its name."
         ), %{params | kafka_label_record: %{}}}

      true ->
        send_to_kafka(data)
        store_in_postgres(data)

        {conn, params}
    end
  end

  defp send_to_kafka(data) do
    groups = Enum.group_by(data, fn [topic | _] -> topic end)

    Enum.each(groups, fn {topic, data} ->
      kafka_data =
        Enum.map(data, fn [_, sign, address, blockchain, label, metadata, datetime] ->
          %{
            sign: sign |> Sanbase.Math.to_integer(),
            address: address,
            blockchain: blockchain,
            label: label,
            metadata: metadata,
            datetime: datetime
          }
        end)
        |> Enum.map(&{"", Jason.encode!(&1)})

      @producer.send_data(topic, kafka_data)
    end)
  end

  defp store_in_postgres(data) do
    insert_data =
      Enum.map(data, fn [topic, sign, address, blockchain, label, metadata, datetime] ->
        {:ok, datetime, _} = DateTime.from_iso8601(datetime)

        %{
          topic: topic,
          sign: sign |> Sanbase.Math.to_integer(),
          address: address,
          blockchain: blockchain,
          label: label,
          metadata: metadata,
          datetime: datetime
        }
      end)

    Sanbase.Repo.insert_all(Sanbase.Model.Kafka.KafkaLabelRecord, insert_data,
      on_conflict: :nothing
    )
  end
end
