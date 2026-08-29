# Between us website

Static website in Simplified Chinese, English, Japanese, and Korean for `betweenus.onecat.dev`, hosted on Cloudflare Pages.

The language menu uses `zh`, `en`, `ja`, and `ko`. It follows the browser language on first visit, falls back to English for other languages, and stores the visitor's choice in `between-us-language`. A selected language can also be shared with the `?lang=` query parameter.

## Stable public URLs

- Landing page: `https://betweenus.onecat.dev/`
- Download redirect: `https://betweenus.onecat.dev/download/`
- Privacy policy: `https://betweenus.onecat.dev/privacy/`
- Terms of use: `https://betweenus.onecat.dev/terms/`
- Purchases and refunds: `https://betweenus.onecat.dev/purchases/`
- Support: `https://betweenus.onecat.dev/support/`

## Publish a TestFlight or App Store release

Edit `release.json`:

```json
{
  "latestVersion": "0.0.2",
  "downloadURL": "https://testflight.apple.com/join/REAL_CODE",
  "isDownloadOpen": true
}
```

Only publish a version after its TestFlight build or App Store product is available. After the App Store release, replace `downloadURL` with the real `https://apps.apple.com/app/id...` product URL. Both the website and the app's update checker read this manifest. Never publish a placeholder code.

## Deploy

From this directory:

```sh
wrangler pages deploy . --project-name between-us --branch main
```

The site has no build step or runtime dependencies.
