defmodule Sanbase.Metric.Registry.Selector do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:type]}

  @primary_key false
  embedded_schema do
    field(:type, :string)
  end

  def changeset(%__MODULE__{} = struct, attrs) do
    struct
    |> cast(attrs, [:type])
    |> validate_required([:type])
  end
end

defmodule Sanbase.Metric.Registry.Table do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:name]}

  @primary_key false
  embedded_schema do
    field(:name, :string)
  end

  def changeset(%__MODULE__{} = struct, attrs) do
    struct
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_format(:name, ~r/[a-z0-9_\-]/)
  end
end

defmodule Sanbase.Metric.Registry.Alias do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:name]}

  @primary_key false
  embedded_schema do
    field(:name, :string)
  end

  def changeset(%__MODULE__{} = struct, attrs) do
    struct
    |> cast(attrs, [:name])
    |> validate_required(:name)
    |> validate_format(:name, Sanbase.Metric.Registry.metric_regex())
    |> validate_length(:name, min: 3, max: 100)
  end
end

defmodule Sanbase.Metric.Registry.Doc do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:link]}

  @primary_key false
  embedded_schema do
    field(:link, :string)
  end

  def changeset(%__MODULE__{} = struct, attrs) do
    struct
    |> cast(attrs, [:link])
    |> validate_required([:link])
    |> validate_format(:link, ~r|https://academy.santiment.net|)
  end
end
