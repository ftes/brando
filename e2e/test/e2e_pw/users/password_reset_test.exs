defmodule E2eProject.E2e.Users.PasswordResetTest do
  use E2eProject.PlaywrightCase

  # The fixtures run in this test's SQL sandbox, picked by the user agent.
  defp password_reset(user_agent, action, body \\ %{}),
    do: fixture(user_agent, "/e2e/password-reset/#{action}", body)

  # Forgetting a password and resetting it by email, and a superuser setting
  # one, are LiveView and controller tests (password_reset_live_test.exs). This
  # one stays for the titled confirmation dialog the reset link goes through.

  test "a superuser sends an editor a reset link from the user form", %{
    page: page,
    sandbox_user_agent: user_agent
  } do
    %{"email" => email} = password_reset(user_agent, "user")

    Page.goto!(page, "/admin/users")
    sync_lv(page)

    page
    |> Page.locator(".content-list .list-row")
    |> Locator.filter(has_text: email)
    |> Locator.get_by_role(:link, name: "Reset Editor")
    |> Locator.click!()

    sync_lv(page)

    Expect.to_have_count!(Page.locator(page, ~s|input[name="user[password]"]|), 0)
    Page.get_by_test_id(page, "send-password-reset") |> Locator.click!()
    dialog = Page.get_by_role(page, :dialog)
    Expect.to_contain_text!(dialog, "Send a password reset link?")
    dialog |> Locator.get_by_role(:button, name: "Send link") |> Locator.click!()
    sync_lv(page)

    Expect.poll!(
      fn -> password_reset(user_agent, "mailbox", %{to: email})["text"] end,
      &assert(&1 =~ "An administrator sent you this link")
    )
  end
end
