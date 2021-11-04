defmodule Sanbase.Kaffy do
  @moduledoc false
  # The kaffy admin uses String.to_existing_atom and fails
  # if there is no atom. Add a bunch of atoms that are needed here.
  @atoms [:accounts]

  @doc false
  def atoms() do
    # Do this only to not have an unused module attribute warning.
    @atoms
  end
end
