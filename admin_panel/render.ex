defimpl ExAdmin.Render, for: Timex.DateTime do
  def to_string(datetime), do: Timex.format!(datetime, "{ISO:Extended}")
end
