# Between us website

Static website in Simplified Chinese, English, Japanese, and Korean for `betweenus.onecat.dev`, hosted on Cloudflare Pages.

The language menu uses `zh`, `en`, `ja`, and `ko`. It follows the browser language on first visit, falls back to English for other languages, and stores the visitor's choice in `between-us-language`. A selected language can also be shared with the `?lang=` query parameter.

## Stable public URLs

- Landing page: `https://betweenus.onecat.dev/`
- Download redirect: `https://betweenus.onecat.dev/download/`
- Privacy policy: `https://betweenus.onecat.dev/privacy/`
- Support: `https://betweenus.onecat.dev/support/`

## Point the download URL at TestFlight or the App Store

Edit `release-config.js`:

```js
window.BETWEEN_US_RELEASE = {
  primaryDownloadURL: "https://testflight.apple.com/join/REAL_CODE",
  channel: "TestFlight",
  available: true
};
```

After the App Store release, replace `primaryDownloadURL` with the real App Store product URL and change `channel` to `App Store`. Never publish a placeholder code.

## Deploy

From this directory:

```sh
wrangler pages deploy . --project-name between-us --branch main
```

The site has no build step or runtime dependencies.
