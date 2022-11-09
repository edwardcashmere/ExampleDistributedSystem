defmodule ExampleDistributedSystem do
  @moduledoc false

  use Application

  def start(_, _) do
    ExampleDistributedSystem.Supervisor.start_link([])
  end
end
