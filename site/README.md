# The BitBinder — marketing site

A fast, dependency-free static landing page for The BitBinder, tuned for
traditional SEO and for AI answer engines (GEO — ChatGPT, Perplexity, Google AI
Overviews, Claude, etc.).

## Files

| File | Purpose |
|---|---|
| `index.html` | Landing page: semantic HTML, meta + Open Graph/Twitter tags, and JSON-LD structured data (MobileApplication, WebSite, FAQPage). |
| `styles.css` | Minimal responsive stylesheet with light/dark support. No frameworks. |
| `robots.txt` | Allows all crawlers and explicitly welcomes AI crawlers (GPTBot, ClaudeBot, PerplexityBot, Google-Extended, Applebot-Extended, …). Points to the sitemap. |
| `sitemap.xml` | Single-page sitemap. |
| `llms.txt` | Concise, factual summary for LLMs/AI search (the emerging `llms.txt` convention). |
| `site.webmanifest` | PWA/manifest metadata. |
| `favicon.svg` | Scalable favicon. |
| `og-image.svg` | Social/share preview image. |

## SEO / GEO features baked in

- One `<h1>`, descriptive `<h2>`/`<h3>`, answer-first copy, and an FAQ that
  mirrors `FAQPage` structured data — the format AI answer engines quote.
- Canonical URL, Open Graph, and Twitter Card tags.
- JSON-LD: `MobileApplication` (with `offers`, `featureList`, App Store
  `downloadUrl`), `WebSite`, and `FAQPage`.
- `robots.txt` that opts in to AI crawlers, plus an `llms.txt` summary.
- No JavaScript required to render content (fast, crawlable, quotable).

## Deploy on GitHub Pages

Two easy options:

1. **Project site from a branch/folder** — In the repo's *Settings → Pages*,
   set the source to this `site/` folder (move it to `/docs` if you prefer, since
   Pages supports `/` or `/docs`). The site will publish at
   `https://taylordrew4u2.github.io/The-Bit-Binder/`.
2. **Any static host** — Upload the contents of `site/` to Netlify, Vercel,
   Cloudflare Pages, or an S3 bucket. No build step.

## Before you go live — update these

- **Domain.** All absolute URLs (canonical, Open Graph, sitemap, robots) use
  `https://taylordrew4u2.github.io/The-Bit-Binder/`. If you use a custom domain
  (e.g. `thebitbinder.app`), find-and-replace that base URL across
  `index.html`, `robots.txt`, `sitemap.xml`, `llms.txt`, and `site.webmanifest`.
- **Share image.** `og-image.svg` renders fine, but some social scrapers
  (iMessage, older Facebook) only preview PNG/JPG. Export a 1200×630 PNG named
  `og-image.png` and point the `og:image`/`twitter:image` tags at it for the
  widest preview support.
- **Verify structured data.** Test `index.html` with Google's Rich Results Test
  and Schema.org validator after deploying.
