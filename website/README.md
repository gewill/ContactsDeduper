# ContactsDeduper website

The site is a dependency-light Vite project that renders static HTML and CSS
for Cloudflare Pages or Direct Upload.

Start a local Vite development server:

```sh
cd website
npm install
npm run dev
```

Open `http://127.0.0.1:5173/en/support/`. Vite serves the generated `dist/`
directory, so rerun `npm run build` after changing source content.

```sh
cd website
npm install
npm run build
npm run check
```

Upload `dist/` to Cloudflare Pages. For a connected repository, use `npm run
build` as the build command and `website/dist` as the output directory.

Privacy content is sourced from the repository's `PRIVACY*.md` files during the
build. The generated pages must not be edited directly.
