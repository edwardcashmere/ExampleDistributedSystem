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
      pong_timeout_ref: nil,
      timeout: 1000,
      elections?: true,
      alive_timeout_ref: nil,
      i_am_the_king_timer_ref: nil,
      alive_replies: [],
      waiting_for_king_reply?: false
    }

    {:ok, default_state, {:continue, :i_am_new}}
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

  # I join cluster and start elections to see if I should be elected King
  @impl true
  def handle_continue(:i_am_new, %{elections?: true} = state) do
    new_state = maybe_begin_elections(state)
    {:noreply, new_state}
  end

  # I get pings by everyone else on the cluster because I am the most senior
  # reply with :pong
  @impl true
  def handle_cast({:ping, from_node}, state) do
    Logger.info("I am the leader i get pinged")
    GenServer.cast({__MODULE__, from_node}, :pong)
    {:noreply, state}
  end

  # receive reply msg from leader
  # cancel reply timout
  # set waiting_for_king_reply? to false
  def handle_cast(
        :pong,
        %{waiting_for_king_reply?: true, pong_timeout_ref: pong_timeout_ref} = state
      ) do
    Logger.info("i received a pong from my leader")
    Process.cancel_timer(pong_timeout_ref)
    new_state = %{state | waiting_for_king_reply?: false, pong_timeout_ref: nil}

    {:noreply, new_state}
  end

  # received pong after timeout
  # discard the pong message
  # elections already began
  def handle_cast(:pong, %{waiting_for_king_reply?: false} = state) do
    Logger.info(" I received ponged msg but the timer already ran out and elections alrady began")
    {:noreply, state}
  end

  # received i_am_the_king msg when elections are ongoing
  # I check if the i_am_the_king_timer_ref was ever set
  # if it was set I cancel the timer and ping the new leader
  # otherwise i just ping the new leader and set the node to leader in state
  def handle_cast(
        {:i_am_the_king, node},
        %{i_am_the_king_timer_ref: i_am_the_king_timer_ref, elections?: true} = state
      ) do
    Logger.info("I am the king #{inspect(node)}")

    new_state =
      if i_am_the_king_timer_ref do
        Process.cancel_timer(i_am_the_king_timer_ref)
        send(self(), :ping)

        %{state | leader: node, i_am_the_king_timer_ref: nil}
      else
        send(self(), :ping)

        %{state | leader: node}
      end

    {:noreply, new_state}
  end

  # received i_am_the_king msg when elections are not happenning
  # I ping the new leader and set the node to leader in state
  def handle_cast(
        {:i_am_the_king, node},
        %{elections?: false} = state
      ) do
    Logger.info("no elections are going on hence #{inspect(node)}")

    send(self(), :ping)

    new_state = %{state | leader: node}

    {:noreply, new_state}
  end

  # reply from senior nodes with :fine_thanks
  # if i_am_the_king_timer_ref is set we cancel it and set it again
  # other wise we are setting it for first time
  # we add the node that replied to alive_replies[] list the we cancel the
  # :alivetimeout timer and set it again
  # we update staate with :alive_timeout, :alive_replies[], i_am_the_king_timer_ref
  def handle_cast(
        {:fine_thanks, node},
        %{
          alive_replies: alive_replies,
          alive_timeout_ref: alive_timeout_ref,
          timeout: timeout,
          i_am_the_king_timer_ref: i_am_the_king_timer_ref
        } = state
      ) do
    Logger.info("Node #{inspect(node())} got a reply from #{inspect(node)}}")

    i_am_the_king_timer_ref =
      if i_am_the_king_timer_ref do
        Process.cancel_timer(i_am_the_king_timer_ref)
        Process.send_after(self(), :i_am_the_king_timeout, timeout)
      else
        Process.send_after(self(), :i_am_the_king_timeout, timeout)
      end

    alive_replies = [node | alive_replies]

    Process.cancel_timer(alive_timeout_ref)
    alive_timeout_ref = Process.send_after(self(), :alive_timeout, timeout)

    new_state = %{
      state
      | alive_timeout_ref: alive_timeout_ref,
        alive_replies: alive_replies,
        i_am_the_king_timer_ref: i_am_the_king_timer_ref
    }

    {:noreply, new_state}
  end

  # we get ping with :alive? msg from juniors
  # with no pong_timeout_ref set
  # if there is a leader set or elections? is ongoing
  # we proclaim ourselves king and reset state
  # otherwise we start elections again
  def handle_cast(
        {:alive?, from_node},
        %{leader: leader, pong_timeout_ref: nil, elections?: elections?} = state
      ) do
    Logger.info("Node #{inspect(node())} is alive?}")
    GenServer.cast({__MODULE__, from_node}, {:fine_thanks, Node.self()})

    if leader == Node.self() or elections? do
      {:noreply, proclaim_myself_king(state)}
    else
      new_state = %{state | elections?: true} |> maybe_begin_elections()

      {:noreply, new_state}
    end
  end

  # when i receive an :alive? message with pong_timeout_ref still set
  # respond with :fine_thanks cancel pong_timeout_ref
  # start elections myself
  # if there is a leader set or elections? ongoing we return state as it is
  # otherwise we start elections
  def handle_cast(
        {:alive?, from_node},
        %{leader: leader, pong_timeout_ref: pong_timeout_ref, elections?: elections?} = state
      ) do
    Logger.info("Node #{inspect(node())} is alive?}")
    GenServer.cast({__MODULE__, from_node}, {:fine_thanks, Node.self()})

    Process.cancel_timer(pong_timeout_ref)

    if leader == Node.self() or elections? do
      {:noreply, %{state | pong_timeout_ref: pong_timeout_ref}}
    else
      new_state =
        %{state | elections?: true, pong_timeout_ref: pong_timeout_ref} |> maybe_begin_elections()

      {:noreply, new_state}
    end
  end

  # none of the senior nodes replied
  # they are then considered dead
  # i proclaim myself king
  # set elections to false
  @impl true
  def handle_info(:alive_timeout, %{alive_replies: [], elections?: true} = state) do
    Logger.info(
      "All seniors are considered dead so I hereby procliam myself king of the westeros"
    )

    {:noreply, proclaim_myself_king(state)}
  end

  # when I receive alive_timout all senior nodes that I asked about their health have replied
  # the nodes that didnt send a reply are pronounced dead
  # if no node reply I promounce myself king and broadcast the message to all other
  def handle_info(:alive_timeout, %{alive_replies: alive_replies, elections?: true} = state) do
    Logger.info("Some heirs from House Targaryan replied , clear I cannot ascend the throne")

    senior_nodes_considered_dead =
      Enum.filter(Node.list(), &(&1 > Node.self())) |> Enum.filter(&(&1 not in alive_replies))

    Enum.each(senior_nodes_considered_dead, fn node ->
      Logger.info("This senior who was next in line to be leader #{inspect(node)} is dead")
    end)

    new_state = %{state | elections?: false}
    {:noreply, new_state}
  end

  def handle_info(:alive_timeout, %{alive_replies: _alive_replies, elections?: false} = state) do
    Logger.info(
      "elections timed out and we have some replies but we are not doing elections discard this message"
    )

    {:noreply, state}
  end

  # if i get i_am_the_king_timeout, i waited for one of the senior nodes to procliam
  # themselves king but they failed hence I become the king
  def handle_info(:i_am_the_king_timeout, state) do
    Logger.info(
      "I waited for any member of House Targaryan to reply reply and be proclaimed king but none replied, so I must ccheck if aim next in line before i scend the throne"
    )

    case check_seniority?() do
      true ->
        Logger.info("I did not get a proclamation hence I become the king")
        {:noreply, proclaim_myself_king(state)}

      _ ->
        new_state = state |> maybe_begin_elections()
        {:noreply, new_state}
    end
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
    if leader == Node.self() do
      {:noreply, state}
    else
      send_ping(leader)
      Process.send_after(self(), :ping, timeout)
      pong_timeout_ref = Process.send_after(self(), :pong_timeout, 4 * timeout)

      new_state = %{state | pong_timeout_ref: pong_timeout_ref, waiting_for_king_reply?: true}
      {:noreply, new_state}
    end
  end

  # handle pong_timout msg
  # basically the king/leader failed to reply
  # we begin elections to name a new leader
  def handle_info(:pong_timeout, %{elections?: false} = state) do
    Logger.info(" the leader did not reply starting elections")
    new_state = %{state | elections?: true, pong_timeout_ref: nil, waiting_for_king_reply?: false}

    new_state = maybe_begin_elections(new_state)

    {:noreply, new_state}
  end

  defp maybe_begin_elections(%{elections?: true, timeout: timeout} = state) do
    # check seniority
    new_state =
      case check_seniority?() do
        true ->
          # broadcast I am the king
          # if senior set myself as leader

          proclaim_myself_king(state)

        false ->
          # ping all senior nodes with :alive? message
          Logger.info("#{inspect(Node.list())} Ping all the possible heirs")

          Node.list()
          |> Enum.filter(&(&1 > Node.self()))
          |> GenServer.abcast(__MODULE__, {:alive?, Node.self()})

          alive_timeout_ref = Process.send_after(self(), :alive_timeout, timeout)
          %{state | alive_timeout_ref: alive_timeout_ref}
      end

    new_state
  end

  defp maybe_begin_elections(%{elections?: false} = state) do
    state
  end

  defp check_seniority?(nodes \\ Node.list()) do
    Enum.all?(nodes, &(&1 < Node.self()))
  end

  defp proclaim_myself_king(state, nodes \\ Node.list()) do
    Logger.info("#{inspect(Node.self())} proclaim myself king")
    GenServer.abcast(nodes, __MODULE__, {:i_am_the_king, Node.self()})
    %{state | leader: Node.self(), elections?: false}
  end

  defp send_ping(node) do
    # Logger.info("ping leader")
    GenServer.cast({__MODULE__, node}, {:ping, Node.self()})
  end
end
