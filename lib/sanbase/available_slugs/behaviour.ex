defmodule Sanbase.AvailableSlugs.Behaviour do
  @moduledoc false
  @callback valid_slug?(String.t()) :: true | false
end
