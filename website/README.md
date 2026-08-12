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

To deploy manually with Wrangler, authenticate with `npx wrangler login` or
set `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`, then run:

```sh
npm run deploy:cf
```

The default Pages project is `contactsdeduper-site` and the default production
branch is `main`. Override them with `CF_PAGES_PROJECT` and `CF_PAGES_BRANCH`.
Configure the custom domain in the Cloudflare Pages dashboard after the first
deployment.

Privacy and Terms of Use content are sourced from the repository's
`PRIVACY*.md` and `TERMS*.md` files during the build. The generated pages must
not be edited directly. The Terms page links to Apple's [Licensed Application
End User License Agreement](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/);
review app-specific terms with counsel before production use.
