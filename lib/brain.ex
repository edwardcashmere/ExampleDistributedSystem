defmodule ExampleDistributedSystem.Brain do
  @moduledoc false
  use GenServer

  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    default_state = %{
      leader: nil,
      pong_timeout: nil,
      timeout: 1000,
      elections?: true,
      alive_timeout: nil,
      i_am_the_king_timer_ref: nil,
      alive_replies: [],
      waiting_for_king_reply?: false
    }

    send(self(), :i_am_new)
    {:ok, default_state}
  end

  # send a message to the :PING leader every 5000msc
  # If he does not reply probably with :PONG start elections
  # track leader, timeout and ongoing_elections? in state

  # if elections are started when the king is not reply("considered dead)
  # send check If  I am the most senior node for Node.list()
  # if i am not the most senior node send :ALIVE? message to
  # all the senior nodes time the reponse should be relied within 5000ms
  # wait for a :FINETHANKS response from all the senior nodes
  # if no node replies after 5000ms broadcast :IMTHEKING message to Node.list()
  # if i receive :FINETHANKS from a node :IMTHEKING for 5000ms ,otherwise I dont receive the message
  # I start the election procedure all over again > send message to start election
  # if i am the most senior i should send message to all the other nodes that :IMTHEKING
  # if i receive :IMTHEKING message i should set the node that sent the message as the new
  # leader and schedule a Ping to him
  # every node that joins the cluster should start elections all over again to see if they should be declared king

  # received ping message from another node
  # reply with :pong
  @impl true
  def handle_cast({:ping, from_node}, state) do
    GenServer.cast({__MODULE__, from_node}, :pong)
    {:noreply, state}
  end

  # receive reply msg from leader
  # cancel reply timout
  # set waiting_for_king_reply? to false

  def handle_cast(
        :pong,
        %{waiting_for_king_reply?: true, pong_timeout: pong_timeout} = state
      ) do
    Process.cancel_timer(pong_timeout)
    new_state = %{state | waiting_for_king_reply?: false}

    {:noreply, new_state}
  end

  # received pong after timeout
  # discard the pong message
  # elections already began
  def handle_cast(:pong, %{waiting_for_king_reply?: false} = state) do
    {:noreply, state}
  end

  def handle_cast(
        {:i_am_the_king, node},
        %{i_am_the_king_timer_ref: i_am_the_king_timer_ref, elections?: true} = state
      ) do
    Process.cancel_timer(i_am_the_king_timer_ref)
    new_state = %{state | leader: node}

    GenServer.cast({__MODULE__, node}, {:ping, Node.self()})

    {:noreply, new_state}
  end

  def handle_cast(
        {:i_am_the_king, node},
        %{elections?: false} = state
      ) do
    new_state = %{state | leader: node}

    GenServer.cast({__MODULE__, node}, {:ping, Node.self()})

    {:noreply, new_state}
  end

  # senior nodes msg received reply
  # with fine thanks
  # track who replied
  # setting a timer for last expected reply
  def handle_cast(
        {:fine_thanks, node},
        %{alive_replies: alive_replies, alive_timeout: alive_timeout, timeout: timeout} = state
      ) do
    alive_replies = [node | alive_replies]

    Process.cancel_timer(alive_timeout)
    alive_timeout = Process.send_after(self(), :alive_timeout, timeout)

    new_state = %{state | alive_timeout: alive_timeout, alive_replies: alive_replies}

    {:noreply, new_state}
  end

  # when i receive an :alive? message
  # respond with :fine_thanks start elections myself
  # if i received alive and i am the most senior proclaim myself king
  def handle_cast({:alive?, from_node}, state) do
    GenServer.cast({__MODULE__, from_node}, {:fine_thanks, Node.self()})

    new_state = %{state | elections?: true} |> maybe_begin_elections()

    {:noreply, new_state}
  end

  # none of the senior nodes replied
  # they are then considered dead
  # i proclaim myself king
  # set elections to false
  @impl true
  def handle_info(:alive_timeout, %{alive_replies: []} = state) do
    IO.puts(" I senior nodes are dead I can ascend the throne")

    proclaim_myself_king()
    new_state = %{state | elections?: false, leader: Node.self()}
    {:noreply, new_state}
  end

  # when I receive alive_timout all senior nodes that I asked about their health have replied
  # the nodes that didnt send a reply are pronounced dead
  # if no node reply I promounce myself king and broadcast the message to all other
  def handle_info(:alive_timeout, %{alive_replies: alive_replies, timeout: timeout} = state) do
    senior_nodes_considered_dead =
      Enum.filter(Node.list(), &(&1 > Node.self())) |> Enum.filter(&(&1 in alive_replies))

    Enum.each(senior_nodes_considered_dead, fn node ->
      IO.inspect("this node #{inspect(node)} is dead")
    end)

    i_am_the_king_timer_ref = Process.send_after(self(), :i_am_the_king_timeout, timeout)

    new_state = %{state | i_am_the_king_timer_ref: i_am_the_king_timer_ref}
    {:noreply, new_state}
  end

  # if i get i_am_the_king_timeout, i waited for one of the senior nodes to procliam
  # themselves king but they failed hence I become the king

  def handle_info(:i_am_the_king_timeout, state) do
    proclaim_myself_king()
    new_state = %{state | leader: Node.self(), elections?: false}
    {:noreply, new_state}
  end

  # recevied ping msg from myself
  # ping the leader although I am still waiting for a reply
  # schedule next ping to myself -> then the  leader
  def handle_info(
        :ping,
        %{leader: leader, timeout: timeout, waiting_for_king_reply?: true} = state
      ) do
    send_ping(leader)
    Process.send_after(self(), :ping, timeout)

    {:noreply, state}
  end

  # receive msg :ping to myself but I am not
  # waiting for a reply from the leader
  # ping the leader
  # schedule reply timeout to be 4 * tap
  # NB timeout should only be cancelled if I receive a reply
  # before the clock runs out
  def handle_info(
        :ping,
        %{leader: leader, timeout: timeout, waiting_for_king_reply?: false} = state
      ) do
    send_ping(leader)
    Process.send_after(self(), :ping, timeout)
    pong_timeout = Process.send_after(self(), :pong_timeout, 4 * timeout)

    new_state = %{state | pong_timeout: pong_timeout}
    {:noreply, new_state}
  end

  # handle pong_timout msg
  # basically the king/leader failed to reply
  # we begin elections to name a new leader
  def handle_info(:pong_timeout, %{elections?: false} = state) do
    new_state = %{state | elections?: true}

    new_state = maybe_begin_elections(new_state)

    {:noreply, new_state}
  end

  # I joined the cluster or rejoined the cluster
  # start elections to see if i should be named king
  def handle_info(:i_am_new, %{elections?: true} = state) do
    new_state = maybe_begin_elections(state)
    {:noreply, new_state}
  end

  # i have received a a king proclaimation from a node()
  # but i am also doing elections update the leader
  # and
  #

  defp maybe_begin_elections(%{elections?: true, timeout: timeout} = state) do
    # check seniority
    new_state =
      case check_seniority?() do
        true ->
          # broadcast I am the king
          # if senior set myself as leader

          proclaim_myself_king()
          IO.inspect("#{inspect(Node.self())} proclaim myself king")
          %{state | leader: Node.self(), elections?: false}

        false ->
          # ping all senior nodes with :alive? message
          IO.inspect("#{inspect(Node.list())} Ping all the possible heirs")

          Node.list()
          |> Enum.filter(&(&1 > Node.self()))
          |> Enum.each(fn node -> GenServer.cast({__MODULE__, node}, {:alive?, Node.self()}) end)

          alive_timeout_tracking = Process.send_after(self(), :alive_timeout, timeout)
          %{state | alive_timeout: alive_timeout_tracking}
      end

    new_state
  end

  defp check_seniority?(nodes \\ Node.list()) do
    Enum.all?(nodes, &(&1 < Node.self())) |> IO.inspect(label: "seniority")
  end

  defp proclaim_myself_king(nodes \\ Node.list()) do
    GenServer.abcast(nodes, __MODULE__, {:i_am_the_king, Node.self()})
  end

  defp send_ping(node) do
    GenServer.cast({__MODULE__, node}, {:ping, Node.self()})
  end
end
