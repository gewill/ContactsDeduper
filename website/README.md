# ContactsDeduper website

The site is intentionally dependency-free. It renders static HTML, CSS, and a
small progressive-enhancement script for Cloudflare Pages or Direct Upload.

```sh
cd website
npm run build
npm run check
```

Upload `dist/` to Cloudflare Pages. For a connected repository, use `npm run
build` as the build command and `website/dist` as the output directory.

Privacy content is sourced from the repository's `PRIVACY*.md` files during the
build. The generated pages must not be edited directly.
