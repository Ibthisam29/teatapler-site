# TeaTapler v2 Hardening + SEO/GEO + RAG + Admin Users

5 revenue streams + full admin + production-grade security.

## What this adds

| Area | Delivers |
|---|---|
| **Security** | RLS roles, rate limits (DB-backed), origin allowlist, Stripe webhook signature verification, idempotency keys, audit log |
| **Admin Users** | Owner/Editor/Viewer roles; first user auto-owner; admin UI to manage them |
| **SEO** | Per-page meta titles/descriptions/OG, admin editor, dynamic sitemap.xml, robots.txt with AI crawlers allowed, JSON-LD org schema |
| **GEO (AI search)** | Per-page `ai_summary` field, auto-generated `/llms.txt` for ChatGPT/Claude/Perplexity, AI-crawler whitelist in robots.txt |
| **RAG** | `rag_knowledge` table with 10 seed entries; admin UI to add/edit; Artello chatbot uses this (no hallucination) |
| **Rate limits** | 10/min per IP on Stripe endpoint; configurable from admin per-endpoint |
| **Site protection** | Maintenance mode toggle, blocked emails/IPs, allowed origins, MFA requirement |
| **Observability** | API logs panel, Stripe events log, rate-limit history |

## Files

| File | Install to |
|---|---|
| `01_hardening_schema.sql` | Supabase SQL Editor → paste → Run |
| `02_create-stripe-link.js` | Replace `netlify/functions/create-stripe-link.js` in repo |
| `03_stripe-webhook.js` | New: `netlify/functions/stripe-webhook.js` in repo |
| `04_sitemap-and-llms.js` | New: `netlify/functions/seo-feed.js` in repo |
| `05_netlify.toml` | New: `netlify.toml` at repo root |
| (admin update) | Replace `teatapler-admin.html` in repo |
| (homepage update) | Replace `index.html` in repo |

## Install order (15 min)

### 1. Run hardening SQL (2 min)
- Supabase → SQL Editor → paste `01_hardening_schema.sql` → Run
- Expect: `v2 hardening applied ✦  rag_entries=10  seo_pages=5  active_admins=1`

### 2. Set Netlify environment variables (3 min)
Netlify Dashboard → Site Configuration → Environment Variables → add:

| Variable | Value |
|---|---|
| `STRIPE_SECRET_KEY` | `sk_live_...` (already set) |
| `STRIPE_WEBHOOK_SECRET` | `whsec_...` (from Stripe webhook — created in step 5) |
| `SUPABASE_URL` | `https://uzzgjdcjkpdccnlpviab.supabase.co` |
| `SUPABASE_ANON_KEY` | your anon public key |
| `SUPABASE_SERVICE_KEY` | your **service_role** key (Supabase → Settings → API → **copy with care**) |

### 3. Upload files to GitHub (5 min)

Repo root:
- `netlify.toml` (new)
- `teatapler-admin.html` (replace)
- `index.html` (replace — paste your anon key into `<meta name="sb-anon" content="...">`)

`netlify/functions/` folder:
- `create-stripe-link.js` (replace)
- `stripe-webhook.js` (new)
- `seo-feed.js` (new)

### 4. Create Stripe webhook (2 min)
Stripe Dashboard → Developers → Webhooks → Add endpoint:
- Endpoint URL: `https://YOUR-NETLIFY-SITE.netlify.app/.netlify/functions/stripe-webhook`
- Events to send: `checkout.session.completed`, `invoice.paid`, `invoice.payment_failed`, `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`
- Copy "Signing secret" (whsec_...) → paste into Netlify env var `STRIPE_WEBHOOK_SECRET`

### 5. Verify (3 min)
Visit these URLs — all should respond:
- `https://teatapler.com/sitemap.xml` (XML list of pages)
- `https://teatapler.com/robots.txt` (AI crawlers allowed)
- `https://teatapler.com/llms.txt` (AI-readable summary + FAQ)

Admin → sign in → check new sidebar sections:
- **Growth** → SEO & GEO, Artello Knowledge
- **Security** → Admin Users, API Logs, Site Protection

## Security posture (post-install)

✅ RLS on every table (public read where needed, admin-only writes)
✅ Role-based access (owner/editor/viewer)
✅ First auth user auto-promoted to owner (or run SQL step 8 manually)
✅ Rate limit: 10 req/min per IP on Stripe endpoint (DB-backed, survives function cold starts)
✅ Origin whitelist (hardcoded + DB-configurable from admin)
✅ Stripe webhook signature verification (timing-safe)
✅ Stripe idempotency keys (duplicate submissions can't create double charges)
✅ Audit log of every Stripe API call + Stripe events deduped
✅ Input validation: price bounds, currency whitelist, mode whitelist, length caps
✅ Security headers: X-Frame-Options, HSTS, CSP-ready, Permissions-Policy
✅ No service key in frontend — only anon key (RLS enforces access)

## MFA (optional)

Enable in Supabase Dashboard → Authentication → Providers → MFA → enable TOTP. Then toggle "Require MFA" in admin → Security → Site Protection. Users will see MFA setup prompt at next sign-in.

## Troubleshooting

- **"has_admin_role does not exist"** → schema didn't run; re-run `01_hardening_schema.sql`
- **"No admins yet" + can't access panels** → run this in SQL editor: `insert into admin_profiles (id, email, role, active) select id, email, 'owner', true from auth.users where email = 'your@email.com' on conflict (id) do update set role = 'owner', active = true;`
- **sitemap.xml 404** → verify `netlify.toml` is in repo root and redeployed
- **Stripe webhook not firing** → check Stripe Dashboard → Webhooks → click your endpoint → "Recent attempts" tab shows errors
- **Rate limit always hits** → check `rate_limits` table in Supabase; delete rows to reset: `delete from rate_limits;`

---
Built for TeaTapler ✦
