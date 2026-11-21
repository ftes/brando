defmodule E2eProject.E2e.Configuration.SeoTest do
  use E2eProject.PlaywrightCase

  # The settings preview, saving, and the meta tags, robots.txt and redirects
  # the site serves from them are LiveView tests in
  # test/brando_admin/live/seo_settings_live_test.exs. What stays here needs a
  # browser: uploading the fallback image and the layout at a phone's width.

  test "the fallback image uploads into the sharing preview, which fits a phone", %{page: page} do
    Page.set_viewport_size!(page, %{width: 1440, height: 1000})
    Page.goto!(page, "/admin")
    Page.get_by_text(page, "Configuration") |> Locator.click!()
    Page.get_by_role(page, :link, name: "SEO") |> Locator.click!()
    Expect.to_have_url!(page, e2e_url("/admin/config/seo"))
    sync_lv(page)

    image_field = Page.locator(page, "#seo_fallback_meta_image-media")

    image_field
    |> Locator.locator(~s|input[type="file"]|)
    |> Locator.set_input_files!(fixture_path("image.jpg"))

    Expect.to_be_visible!(Locator.locator(image_field, "img"), timeout: 30_000)
    sync_lv(page)
    Expect.to_have_count!(Page.get_by_text(page, "No image associated with"), 0)
    Expect.to_be_visible!(Page.locator(page, ".seo-sharing-preview img"))
    Page.get_by_test_id(page, "submit") |> Locator.click!()
    Expect.to_have_url!(page, e2e_url("/admin/config/seo"))
    sync_lv(page)

    Page.evaluate!(page, "window.scrollTo(0, 0)")
    Expect.poll!(fn -> Page.evaluate!(page, "window.scrollY") end, &assert(&1 == 0))

    Page.screenshot!(page,
      path: Playwright.Test.output_path("seo-populated-desktop.png"),
      full_page: true,
      animations: :disabled
    )

    Page.set_viewport_size!(page, %{width: 390, height: 844})
    Expect.poll!(fn -> Page.evaluate!(page, "document.documentElement.scrollWidth") end, &assert(&1 <= 390))
    Expect.to_be_visible!(Page.locator(page, ".seo-sharing-preview img"))

    Page.screenshot!(page,
      path: Playwright.Test.output_path("seo-populated-mobile.png"),
      full_page: true,
      animations: :disabled
    )
  end
end
