defmodule E2eProject.PlaywrightCase do
  @moduledoc """
  Port of playwright/test-support/setupAuth.js and utils.js for playwright_ex.

  Gives each test a `page` logged in as the seeded admin, bound to this test's SQL
  sandbox (picked by the user agent), plus `sandbox_user_agent` and
  `second_user_page/1` for multi-user tests.
  """
  use ExUnit.CaseTemplate

  # In place of the ExUnit.Assertions that ExUnit.CaseTemplate imports: asserts as steps.
  import ExUnit.Assertions, only: []
  import Playwright.Test.Assertions

  alias Playwright.{Browser, BrowserContext, Expect, Locator, Page}

  using opts do
    opts =
      opts
      |> Keyword.put_new(:async, false)
      |> Keyword.put_new(:parameterize, quote(do: E2eProject.PlaywrightCase.projects()))

    quote do
      use Playwright.Case, unquote(opts)
      import E2eProject.PlaywrightCase

      @moduletag :e2e

      setup %{browser: browser} do
        user_agent = E2eProject.PlaywrightCase.checkout_sandbox!()
        ExUnit.Callbacks.on_exit(fn -> E2eProject.PlaywrightCase.checkin_sandbox(user_agent) end)

        {_context, page} =
          E2eProject.PlaywrightCase.build_user_page(browser, user_agent, "admin@brandocms.com")

        %{page: page, sandbox_user_agent: user_agent}
      end
    end
  end

  @doc "playwright.config.js's projects, as `parameterize:` takes them."
  def projects do
    [
      Playwright.Test.parameters(
        [name: "Google Chrome"] ++ Playwright.device("Desktop Chrome") ++ [channel: "chromium"]
      )
    ]
  end

  def base_url, do: Playwright.Test.config().context_options[:base_url]

  def e2e_url(path), do: base_url() <> path

  def checkout_sandbox! do
    {200, body, _headers} = http(:post, "/sandbox", [], "", nil)
    "BeamMetadata" <> _ = body
    body
  end

  def checkin_sandbox(user_agent), do: http(:delete, "/sandbox", [], "", user_agent)

  # POST to a fixture route inside this test's sandbox and decode the JSON reply.
  def fixture(user_agent, path, body \\ %{}) do
    {status, response, _headers} =
      http(:post, path, [{~c"content-type", ~c"application/json"}], JSON.encode!(body), user_agent)

    true = status in 200..299
    JSON.decode!(response)
  end

  def build_user_page(browser, user_agent, email) do
    {_status, _body, headers} = http(:post, "/e2e/login/#{email}", [], "", user_agent)

    context = Browser.new_context!(browser, base_url: base_url(), user_agent: user_agent)

    cookies =
      for {~c"set-cookie", value} <- headers do
        [pair | _] = value |> to_string() |> String.split(";")
        [name, val] = String.split(String.trim(pair), "=", parts: 2)
        %{name: name, value: val, domain: "localhost", path: "/", httpOnly: false, secure: false, sameSite: "Lax"}
      end

    if cookies != [], do: BrowserContext.add_cookies!(context, cookies)

    # Hide toast notifications so they don't intercept pointer events in tests
    BrowserContext.add_init_script!(context, """
    (() => {
      const style = document.createElement('style')
      style.textContent = '.toast-stack { display: none !important; }'
      const inject = () => document.head?.appendChild(style.cloneNode(true))
      if (document.head) inject()
      else document.addEventListener('DOMContentLoaded', inject)
    })()
    """)

    {context, BrowserContext.new_page!(context)}
  end

  def second_user_page(%{browser: browser, sandbox_user_agent: user_agent}) do
    {_context, page} = build_user_page(browser, user_agent, "editor@brandocms.com")
    page
  end

  defp http(method, path, headers, body, user_agent) do
    url = String.to_charlist(e2e_url(path))
    headers = if user_agent, do: [{~c"user-agent", String.to_charlist(user_agent)} | headers], else: headers

    request =
      case method do
        :post -> {url, headers, ~c"application/json", body}
        :delete -> {url, headers}
      end

    {:ok, {{_, status, _}, resp_headers, resp_body}} =
      :httpc.request(method, request, [], body_format: :binary)

    {status, resp_body, resp_headers}
  end

  @doc "Port of syncLV: wait until the LiveView has no pending events."
  def sync_lv(page, timeout \\ 15_000) do
    Expect.to_be_visible!(Page.locator(page, ".phx-connected") |> Locator.first(), timeout: timeout)
    Expect.to_have_count!(Page.locator(page, "[data-phx-session]:not(.phx-connected)"), 0, timeout: timeout)
    Expect.to_have_count!(Page.locator(page, ".phx-change-loading"), 0, timeout: timeout)
    Expect.to_have_count!(Page.locator(page, ".phx-click-loading"), 0, timeout: timeout)
    Expect.to_have_count!(Page.locator(page, ".phx-submit-loading"), 0, timeout: timeout)
    :ok
  end

  def fixture_path(name), do: Path.expand("playwright/fixtures/#{name}")

  @doc "Port of setEntryStatus in utils.js."
  def set_entry_status(page, status) do
    trigger = Page.get_by_test_id(page, "status-trigger")
    Locator.click!(trigger)
    Expect.to_have_attribute!(trigger, "aria-expanded", "true")

    page
    |> Page.get_by_test_id("status-options")
    |> Locator.locator(~s|label:has(input[value="#{status}"])|)
    |> Locator.click!()

    Expect.to_have_attribute!(trigger, "data-status", status)
    Expect.to_have_attribute!(trigger, "aria-expanded", "false")
  end

  @doc "Port of waitForPreviewReady in utils.js."
  def wait_for_preview_ready(page) do
    Page.locator(page, ".live-preview-wrapper iframe")
    |> Locator.wait_for!(state: :visible, timeout: 30_000)

    page
    |> Page.frame_locator(".live-preview-wrapper iframe")
    |> Playwright.FrameLocator.locator("body *")
    |> Locator.first()
    |> Locator.wait_for!(state: :attached, timeout: 30_000)
  end

  # Port of routeLiveSocket / dropConnection / restoreConnection in utils.js. A lost
  # connection, the way sleep or a network change loses it: the socket dies without a
  # clean close and the retries are refused until `restore_connection`. Call
  # `route_live_socket` before the page loads; it returns the state to pass on.
  def route_live_socket(page) do
    {:ok, live} = Agent.start_link(fn -> %{refused: false, sockets: []} end)

    Page.route_web_socket!(page, ~r"/live/websocket", fn ws ->
      if Agent.get(live, & &1.refused) do
        Playwright.WebSocketRoute.close(ws, code: 4001, reason: "e2e: connection lost")
      else
        server = Playwright.WebSocketRoute.connect_to_server(ws)
        Agent.update(live, &%{&1 | sockets: [{ws, server} | &1.sockets]})
      end
    end)

    live
  end

  def drop_connection(page, live) do
    sockets = Agent.get_and_update(live, &{&1.sockets, %{&1 | refused: true, sockets: []}})

    for {ws, server} <- sockets do
      Playwright.WebSocketRoute.close(ws, code: 4001, reason: "e2e: connection lost")
      Playwright.WebSocketRoute.close(server)
    end

    Expect.to_be_hidden!(Page.locator(page, ".phx-connected") |> Locator.first(), timeout: 15_000)
  end

  def restore_connection(page, live) do
    Agent.update(live, &%{&1 | refused: false})
    sync_lv(page, 30_000)
  end

  @doc "POST /__e2e/db/factory and return the decoded row."
  def factory(page, schema, attributes) do
    response =
      Playwright.APIRequestContext.post!(Page.request(page), "/__e2e/db/factory",
        data: %{schema: schema, attributes: attributes, creator_id: 1, fields: ["id"]}
      )

    assert Playwright.APIResponse.ok(response), Playwright.APIResponse.text!(response)
    Playwright.APIResponse.json!(response)
  end
end
