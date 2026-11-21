defmodule E2eProject.Latency do
  @moduledoc """
  Port of playwright/test-support/latency.js: holds back LiveView frames from the
  server, in order, so a test can see what the page shows before the server has answered.

      latency = E2eProject.Latency.install(page)  # before Page.goto!
      E2eProject.Latency.set(latency, 1500)
  """
  alias Playwright.{Page, WebSocketRoute}

  def install(page) do
    {:ok, pump} = GenServer.start_link(E2eProject.Latency.Pump, nil)

    Page.route_web_socket!(page, "**/live/websocket*", fn ws ->
      server = WebSocketRoute.connect_to_server(ws)
      WebSocketRoute.on_message(server, fn message -> GenServer.cast(pump, {:frame, ws, message}) end)
    end)

    pump
  end

  def set(pump, ms), do: GenServer.cast(pump, {:set, ms})
end

defmodule E2eProject.Latency.Pump do
  @moduledoc false
  use GenServer

  def init(_), do: {:ok, %{delay: 0, last: 0}}

  def handle_cast({:set, ms}, state), do: {:noreply, %{state | delay: ms}}

  def handle_cast({:frame, ws, message}, state) do
    now = System.system_time(:millisecond)
    # Never earlier than the frame before it: lowering the delay must not
    # reorder frames already held.
    at = max(now + state.delay, state.last)
    Process.send_after(self(), {:flush, ws, message}, max(at - now, 0))
    {:noreply, %{state | last: at}}
  end

  def handle_info({:flush, ws, message}, state) do
    try do
      Playwright.WebSocketRoute.send(ws, message)
    catch
      _, _ -> :ok
    end

    {:noreply, state}
  end
end
