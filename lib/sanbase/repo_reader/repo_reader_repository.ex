defmodule Sanbase.RepoReader.Repository do
  @moduledoc false
  defstruct path: nil

  @type t :: %__MODULE__{
          path: String.t()
        }
end
