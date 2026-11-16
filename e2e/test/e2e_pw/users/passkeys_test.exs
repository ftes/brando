defmodule E2eProject.E2e.Users.PasskeysTest do
  use E2eProject.PlaywrightCase

  alias Playwright.CDPSession

  # The fixtures run in this test's SQL sandbox, picked by the user agent.
  defp two_factor(user_agent, action, body \\ %{}),
    do: fixture(user_agent, "/e2e/two-factor/#{action}", body)

  # Chromium's virtual authenticator stands in for a phone or a fingerprint
  # reader: it makes and uses passkeys without asking.
  defp virtual_authenticator(page) do
    client = BrowserContext.new_cdp_session!(Page.context(page), page)
    CDPSession.send!(client, "WebAuthn.enable")

    %{"authenticatorId" => authenticator_id} =
      CDPSession.send!(client, "WebAuthn.addVirtualAuthenticator", %{
        options: %{
          protocol: "ctap2",
          transport: "internal",
          hasResidentKey: true,
          hasUserVerification: true,
          isUserVerified: true,
          automaticPresenceSimulation: true
        }
      })

    {client, authenticator_id}
  end

  # GET /admin/logout only asks; its button signs out (a DELETE)
  defp log_out(page) do
    Page.goto!(page, "/admin/logout")
    sync_lv(page)
    Page.get_by_test_id(page, "logout-confirm") |> Locator.click!()
    Expect.to_have_url!(page, e2e_url("/admin/login"))
  end

  defp log_in(page, email, password) do
    Page.goto!(page, "/admin/login")
    sync_lv(page)
    Page.get_by_test_id(page, "email") |> Locator.fill!(email)
    Page.get_by_test_id(page, "password") |> Locator.fill!(password)
    Page.get_by_test_id(page, "login-button") |> Locator.click!()
  end

  defp new_page(browser, user_agent) do
    context = Browser.new_context!(browser, base_url: base_url(), user_agent: user_agent)
    {context, BrowserContext.new_page!(context)}
  end

  test "a user adds a passkey, logs in with it alone, and as the second step", %{
    browser: browser,
    sandbox_user_agent: user_agent
  } do
    %{"email" => email, "password" => password} = two_factor(user_agent, "user")
    {context, page} = new_page(browser, user_agent)

    try do
      {client, authenticator_id} = virtual_authenticator(page)
      log_in(page, email, password)
      Expect.to_have_url!(page, e2e_url("/admin"))

      Page.goto!(page, "/admin/users/security")
      sync_lv(page)
      Page.get_by_test_id(page, "passkey-add") |> Locator.click!()
      modal = Page.locator(page, "#passkey-add-modal")
      Expect.to_be_visible!(modal)
      modal |> Locator.get_by_test_id("passkey-name") |> Locator.fill!("Work laptop")
      # A session alone does not add a passkey
      modal |> Locator.get_by_test_id("passkey-proof") |> Locator.fill!("not my password")
      modal |> Locator.get_by_test_id("passkey-create") |> Locator.click!()
      Expect.to_be_visible!(Locator.get_by_test_id(modal, "passkey-error"))

      %{"credentials" => none} =
        CDPSession.send!(client, "WebAuthn.getCredentials", %{authenticatorId: authenticator_id})

      assert none == []

      modal |> Locator.get_by_test_id("passkey-proof") |> Locator.fill!(password)
      Page.screenshot!(page, path: Playwright.Test.output_path("add-passkey.png"))
      modal |> Locator.get_by_test_id("passkey-create") |> Locator.click!()

      # The first second factor comes with recovery codes
      page
      |> Page.locator("#recovery-codes-modal")
      |> Locator.get_by_test_id("recovery-code")
      |> Expect.to_have_count!(10)

      Page.get_by_test_id(page, "recovery-codes-done") |> Locator.click!()
      Expect.to_have_count!(Page.get_by_test_id(page, "passkey"), 1)
      Expect.to_contain_text!(Page.get_by_test_id(page, "passkey"), "Work laptop")
      Expect.to_have_attribute!(Page.get_by_test_id(page, "two-factor-status"), "data-enabled", "true")

      %{"credentials" => credentials} =
        CDPSession.send!(client, "WebAuthn.getCredentials", %{authenticatorId: authenticator_id})

      assert length(credentials) == 1

      # A passkey alone logs in
      log_out(page)
      Page.goto!(page, "/admin/login")
      sync_lv(page)
      Page.get_by_test_id(page, "login-passkey") |> Locator.click!()
      Expect.to_have_url!(page, e2e_url("/admin"))

      # After the password, the passkey is the second step
      log_out(page)
      log_in(page, email, password)
      Expect.to_have_url!(page, e2e_url("/admin/login/two-factor"))
      sync_lv(page)
      Page.screenshot!(page, path: Playwright.Test.output_path("second-step.png"))
      Page.get_by_test_id(page, "two-factor-passkey") |> Locator.click!()
      Expect.to_have_url!(page, e2e_url("/admin"))

      # Where the user is logged in
      Page.goto!(page, "/admin/users/security")
      sync_lv(page)
      Expect.to_have_count!(Page.locator(page, "[data-testid=session][data-current=true]"), 1)
    after
      BrowserContext.close!(context)
    end
  end

  test "a sensitive action asks for the password again after a while", %{
    browser: browser,
    sandbox_user_agent: user_agent
  } do
    %{"email" => email, "password" => password} = two_factor(user_agent, "user")
    {context, page} = new_page(browser, user_agent)

    try do
      log_in(page, email, password)
      Expect.to_have_url!(page, e2e_url("/admin"))
      two_factor(user_agent, "stale-sessions", %{email: email})

      Page.goto!(page, "/admin/users/security")
      sync_lv(page)
      Page.get_by_test_id(page, "passkey-add") |> Locator.click!()
      prompt = Page.locator(page, "#reauth-modal")
      Expect.to_be_visible!(prompt)
      Expect.to_have_count!(Page.locator(page, "#passkey-add-modal"), 0)

      prompt |> Locator.get_by_test_id("reauth-proof") |> Locator.fill!("not my password")
      prompt |> Locator.get_by_test_id("reauth-submit") |> Locator.click!()
      Expect.to_be_visible!(Locator.get_by_test_id(prompt, "reauth-error"))

      prompt |> Locator.get_by_test_id("reauth-proof") |> Locator.fill!(password)
      prompt |> Locator.get_by_test_id("reauth-submit") |> Locator.click!()
      Expect.to_have_count!(Page.locator(page, "#reauth-modal"), 0)
      # The action it held goes ahead
      Expect.to_be_visible!(Page.locator(page, "#passkey-add-modal"))
    after
      BrowserContext.close!(context)
    end
  end

  test "a screen that needs it sends a stale session to confirm first, and back", %{
    page: page,
    sandbox_user_agent: user_agent
  } do
    two_factor(user_agent, "stale-sessions", %{email: "admin@brandocms.com"})

    Page.goto!(page, "/admin/users/sign-in-policy")
    Expect.to_have_url!(page, ~r"/admin/confirm\?return_to=")
    sync_lv(page)
    Page.get_by_test_id(page, "reauth-proof") |> Locator.fill!("brandocms")
    Page.get_by_test_id(page, "reauth-submit") |> Locator.click!()
    Expect.to_have_url!(page, e2e_url("/admin/users/sign-in-policy"))
  end
end
