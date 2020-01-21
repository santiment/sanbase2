defmodule Sanbase.Model.Kafka.KafkaLabelRecord do
  use Ecto.Schema
  import Ecto.Changeset
  require Logger

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
          raw(
            "CSV Format: topic, sign, address, blockchain, label, metadata, ISO8601 datetime string or timestmap"
          )
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

    cond do
      not all_present? ->
        Logger.warn("Exporing labels to kafka failed. Reason: There are missing fields")

        {Phoenix.Controller.put_flash(
           conn,
           :error,
           "All fields except metadata are mandatory."
         ), %{params | kafka_label_record: %{}}}

      Enum.any?(datetimes, fn
        dt when is_binary(dt) ->
          match?({:error, _}, DateTime.from_iso8601(dt))

        timestamp when is_integer(timestamp) ->
          match?({:error, _}, DateTime.from_unix(timestamp))
      end) ->
        Logger.warn("Exporing labels to kafka failed. Reason: Invalid datetime value")

        {Phoenix.Controller.put_flash(
           conn,
           :error,
           "All datetimes must be valid ISO8601 string formatted datetimes."
         ), %{params | kafka_label_record: %{}}}

      not Enum.all?(topics, &String.contains?(&1, "label")) ->
        Logger.warn(
          "Exporing labels to kafka failed. Reason: The kafka topic must contain `label` in its name                                    q"
        )

        {Phoenix.Controller.put_flash(
           conn,
           :error,
           "Every topic must contain 'label' in its name."
         ), %{params | kafka_label_record: %{}}}

      true ->
        Logger.info("Sending address labels to kafka imported via the admin panel...")

        with {:kafka, :ok} <- {:kafka, send_to_kafka(data)},
             {:postgres, {num, _}} when is_integer(num) <- {:postgres, store_in_postgres(data)} do
          {conn, params}
        else
          {:kafka, {:error, error}} ->
            error_msg = "Error exporting the labels to kafka. Reason: #{inspect(error)}"
            Logger.warn(error_msg)

            {Phoenix.Controller.put_flash(
               conn,
               :error,
               error_msg
             ), %{params | kafka_label_record: %{}}}

          {:postgres, _} ->
            error_msg = "The labels could not be stored in postrgres"
            Logger.warn(error_msg)

            {Phoenix.Controller.put_flash(
               conn,
               :error,
               error_msg
             ), %{params | kafka_label_record: %{}}}
        end
    end
  end

  defp send_to_kafka(data) do
    Logger.info("Exporting labels to kafka via the admin panel...")

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
            timestamp: datetime |> to_timestamp()
          }
        end)
        |> Enum.map(&{"", Jason.encode!(&1)})

      @producer.send_data(topic, kafka_data)
    end)
  end

  defp to_timestamp(dt_str) when is_binary(dt_str) do
    Sanbase.DateTimeUtils.from_iso8601!(dt_str)
    |> DateTime.to_unix()
  end

  defp to_timestamp(timestamp) when is_integer(timestamp), do: timestamp

  defp to_timestamp(%DateTime{} = dt), do: DateTime.to_unix(dt)

  defp to_dt_struct(dt_str) when is_binary(dt_str),
    do: Sanbase.DateTimeUtils.from_iso8601!(dt_str)

  defp to_dt_struct(timestamp) when is_integer(timestamp),
    do: DateTime.from_unix!(timestamp)

  defp to_dt_struct(%DateTime{} = dt), do: dt

  defp store_in_postgres(data) do
    Logger.info("Exporting labels to postgres via the admin panel...")

    insert_data =
      Enum.map(data, fn [topic, sign, address, blockchain, label, metadata, datetime] ->
        %{
          topic: topic,
          sign: sign |> Sanbase.Math.to_integer(),
          address: address,
          blockchain: blockchain,
          label: label,
          metadata: metadata,
          datetime: datetime |> to_dt_struct()
        }
      end)

    Sanbase.Repo.insert_all(Sanbase.Model.Kafka.KafkaLabelRecord, insert_data,
      on_conflict: :nothing
    )
  end
end
