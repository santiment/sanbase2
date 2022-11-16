defmodule Sanbase.RepoReader.Repository do
  defstruct path: nil

  @type t :: %__MODULE__{
          path: String.t()
        }
end
