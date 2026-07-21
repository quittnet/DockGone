# JBECS Group — Sample Website (image-free)

A clean, responsive rebuild of the [jbecs.com](https://jbecs.com) concept,
built as a **static site with no images**. Every visual — icons, the brand
mark, backgrounds, dividers — is rendered with CSS gradients and inline SVG,
so there are zero raster/photo assets to load. It's ready to deploy to
**Cloudflare Pages**.

> Note: the original site could not be reached from the build environment
> (network policy + `403`), so content is modeled on the public JBECS Group
> brand — *"Engineering Strength. Building Futures."* — a multi-industry group
> spanning construction, agriculture, logistics, and energy. Copy is sample
> placeholder text; swap in real content freely.

## Files

| File | Purpose |
|------|---------|
| `index.html` | Full single-page site (hero, stats, about, divisions, services, industries, contact, footer) |
| `styles.css` | All styling — tokens, layout, responsive rules |
| `main.js` | Mobile navigation toggle |
| `wrangler.toml` | Cloudflare Pages project config |
| `_headers` | Security + caching headers for Pages |
| `package.json` | `dev` / `deploy` scripts |

## Preview locally

Any static server works — no build step:

```bash
# Python
python3 -m http.server 8080
# then open http://localhost:8080

# …or with Wrangler (emulates Pages)
npx wrangler pages dev .
```

## Deploy to Cloudflare Pages

### Option A — Direct upload with Wrangler (fastest)

```bash
cd website
npm install
npx wrangler login            # authenticate with your Cloudflare account
npm run deploy                # uploads this folder to a "jbecs-group" Pages project
```

Wrangler prints a `*.pages.dev` URL when it finishes.

### Option B — Connect the Git repo in the dashboard

1. Cloudflare dashboard → **Workers & Pages** → **Create** → **Pages** →
   **Connect to Git**.
2. Pick this repository and branch.
3. Build settings:
   - **Framework preset:** None
   - **Build command:** *(leave empty)*
   - **Build output directory:** `website`
4. **Save and Deploy.** Pushes to the branch auto-deploy.

## Customizing

- **Colors / fonts:** edit the `:root` tokens at the top of `styles.css`.
- **Copy & sections:** edit `index.html` directly.
- **Contact form:** it's a non-submitting sample. Wire it to a
  [Pages Function](https://developers.cloudflare.com/pages/functions/) or a form
  service to make it live.
