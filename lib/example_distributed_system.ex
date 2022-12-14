defmodule ExampleDistributedSystem do
  @moduledoc false

  require Logger

  use Application

  def start(_, _) do
    ExampleDistributedSystem.Supervisor.start_link([])
    # get nodes from env , maybe add a make file to start all nodes on separate kernels
    # connect nodes if any
    # start my worker and maybe get elected as the king
    case Application.get_env(:example_distributed_system, :nodes, []) do
      [] ->
        Logger.info("No nodes found")

      [_ | _] = nodes ->
        start_node_and_connect(nodes)
    end
  end

  defp join_cluster do
    DynamicSupervisor.start_child(
      ExampleDistributedSystem.DynamicSupervisor,
      {ExampleDistributedSystem.Brain, []}
    )
  end

  def leave_cluster do
    DynamicSupervisor.terminate_child(
      ExampleDistributedSystem.DynamicSupervisor,
      :erlang.whereis(ExampleDistributedSystem.Brain)
    )
  end

  def check_state do
    :sys.get_state(ExampleDistributedSystem.Brain)
  end

  defp start_node_and_connect(nodes) do
    case Enum.reject(nodes, fn node -> node in connect_to_node(nodes) end) do
      [] ->
        Logger.error("all nodes failed to connect")

      connected_nodes ->
        Logger.info("#{inspect(connected_nodes)} nodes connected succesfuly")
    end

    join_cluster()
  end

  defp connect_to_node([]), do: []

  defp connect_to_node([node | other_nodes]) do
    case Node.connect(node) do
      true ->
        connect_to_node(other_nodes)

      false ->
        [node | connect_to_node(other_nodes)]

      :ignored ->
        Logger.error(" node #{node} not started")
    end
  end
end
