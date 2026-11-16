defmodule E2eProject.E2e.Users.PresenceAvatarsTest do
  use E2eProject.PlaywrightCase

  defp expect_contained_photo(avatar) do
    photo = Locator.locator(avatar, "img")
    Expect.to_be_visible!(photo)
    Expect.poll!(fn -> Locator.evaluate!(photo, "img => img.naturalWidth") end, &assert(&1 > 0))

    # Check the rendered bounds, not just CSS declarations: an intrinsic-width
    # image wrapper can escape the small flex avatar and cover the form.
    Expect.poll!(
      fn ->
        Locator.evaluate!(avatar, """
        el => {
          const outer = el.getBoundingClientRect()
          const inner = el.querySelector('img').getBoundingClientRect()
          return inner.width > 0 && inner.height > 0 &&
            inner.left >= outer.left - 1 && inner.top >= outer.top - 1 &&
            inner.right <= outer.right + 1 && inner.bottom <= outer.bottom + 1
        }
        """)
      end,
      &assert(&1 == true)
    )
  end

  test "presence photos stay inside toolbar and field avatars through form patches", %{page: page} = ctx do
    second_user_page = second_user_page(ctx)
    Page.set_viewport_size!(page, %{width: 1440, height: 1000})
    Page.set_viewport_size!(second_user_page, %{width: 1440, height: 1000})
    response = Playwright.APIRequestContext.post!(Page.request(page), "/e2e/user-directory/create")
    assert Playwright.APIResponse.ok(response)
    fixture = Playwright.APIResponse.json!(response)

    try do
      Page.goto!(page, "/admin/pages/update/1")
      sync_lv(page)

      toolbar_avatar =
        page
        |> Page.locator(".page-presences")
        |> Locator.get_by_role(:img, name: "Brando Admin", exact: true)

      expect_contained_photo(toolbar_avatar)
      Expect.to_have_css!(toolbar_avatar, "width", "30px")

      Page.goto!(second_user_page, "/admin/pages/update/1")
      sync_lv(second_user_page)

      remote_toolbar_avatar =
        second_user_page
        |> Page.locator(".page-presences")
        |> Locator.get_by_role(:img, name: "Brando Admin", exact: true)

      expect_contained_photo(remote_toolbar_avatar)
      Expect.to_be_visible!(Page.locator(second_user_page, ".page-presences .avatar-placeholder"))

      Page.get_by_label(page, "Title", exact: true) |> Locator.click!()
      locked_field = Page.locator(second_user_page, ".field-wrapper.field-locked")
      Expect.to_have_count!(locked_field, 1)
      field_avatar = Locator.locator(locked_field, ".field-presence-user .avatar")
      expect_contained_photo(field_avatar)
      Expect.to_have_css!(field_avatar, "width", "14px")

      Page.get_by_label(second_user_page, "URI", exact: true) |> Locator.fill!("presence-avatar-check")
      sync_lv(second_user_page)
      expect_contained_photo(remote_toolbar_avatar)
      expect_contained_photo(field_avatar)
      Expect.to_be_hidden!(Page.locator(second_user_page, "body > canvas"))

      Page.screenshot!(second_user_page,
        path: Playwright.Test.output_path("presence-avatars-desktop.png"),
        full_page: false
      )
    after
      Playwright.APIRequestContext.post!(Page.request(page), "/e2e/user-directory/cleanup", data: fixture)
    end
  end
end
