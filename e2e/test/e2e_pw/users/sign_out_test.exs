defmodule E2eProject.E2e.Users.SignOutTest do
  use E2eProject.PlaywrightCase

  # The fixtures run in this test's SQL sandbox, picked by the user agent.
  defp two_factor(user_agent, action, body \\ %{}),
    do: fixture(user_agent, "/e2e/two-factor/#{action}", body)

  defp log_in(page, email, password) do
    Page.goto!(page, "/admin/login")
    sync_lv(page)
    Page.get_by_test_id(page, "email") |> Locator.fill!(email)
    Page.get_by_test_id(page, "password") |> Locator.fill!(password)
    Page.get_by_test_id(page, "login-button") |> Locator.click!()
    Expect.to_have_url!(page, e2e_url("/admin"))
  end

  test "the account menu signs out", %{page: page} do
    Page.goto!(page, "/admin")
    sync_lv(page)

    Page.get_by_test_id(page, "current-user") |> Locator.click!()
    Page.get_by_test_id(page, "logout") |> Locator.click!()
    Expect.to_have_url!(page, e2e_url("/admin/login"))

    Page.goto!(page, "/admin")
    Expect.to_have_url!(page, e2e_url("/admin/login"))
  end

  test "GET /admin/logout only asks, and nothing else signs out", %{page: page} do
    # Neither a plain GET nor a DELETE without the CSRF token, as another site could send
    request = Page.request(page)
    assert Playwright.APIResponse.ok(Playwright.APIRequestContext.get!(request, "/admin/logout"))

    assert Playwright.APIResponse.status(
             Playwright.APIRequestContext.delete!(request, "/admin/logout", max_redirects: 0)
           ) == 403

    Page.goto!(page, "/admin/logout")
    sync_lv(page)
    Page.get_by_test_id(page, "logout-cancel") |> Locator.click!()
    Expect.to_have_url!(page, e2e_url("/admin"))

    Page.goto!(page, "/admin/logout")
    sync_lv(page)
    Page.get_by_test_id(page, "logout-confirm") |> Locator.click!()
    Expect.to_have_url!(page, e2e_url("/admin/login"))
    Page.goto!(page, "/admin")
    Expect.to_have_url!(page, e2e_url("/admin/login"))
  end

  test "logging out a session from another browser closes its open admin", %{
    browser: browser,
    sandbox_user_agent: user_agent
  } do
    %{"email" => email, "password" => password} = two_factor(user_agent, "user")
    first = Browser.new_context!(browser, base_url: base_url(), user_agent: user_agent)
    second = Browser.new_context!(browser, base_url: base_url(), user_agent: user_agent)

    try do
      open = BrowserContext.new_page!(first)
      log_in(open, email, password)
      sync_lv(open)

      other = BrowserContext.new_page!(second)
      log_in(other, email, password)
      Page.goto!(other, "/admin/users/security")
      sync_lv(other)

      other
      |> Page.locator("[data-testid=session][data-current=false]")
      |> Locator.get_by_test_id("session-revoke")
      |> Locator.click!()

      Expect.to_have_count!(Page.get_by_test_id(other, "session"), 1)

      # Disconnected, the open page goes back to log in by itself
      Expect.to_have_url!(open, e2e_url("/admin/login"), timeout: 15_000)

      # The other browser is still in
      Page.goto!(other, "/admin")
      Expect.to_have_url!(other, e2e_url("/admin"))
    after
      BrowserContext.close!(first)
      BrowserContext.close!(second)
    end
  end
end
