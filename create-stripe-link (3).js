// netlify/functions/create-stripe-link.js  (v2 HARDENED)
// Replace the current file in your repo with this version.
// Env vars required in Netlify:
//   STRIPE_SECRET_KEY = sk_live_... or sk_test_...
//   SUPABASE_URL = https://uzzgjdcjkpdccnlpviab.supabase.co
//   SUPABASE_SERVICE_KEY = eyJ...  (service role key — Supabase Settings > API)

const ALLOWED_ORIGINS = [
  'https://teatapler.com',
  'https://www.teatapler.com',
  'https://ibthisam29.github.io',
  'http://localhost:3000',
];
const RATE_LIMIT_PER_MIN = 10;

exports.handler = async (event) => {
  const origin = event.headers.origin || event.headers.Origin || '';
  const isAllowed = ALLOWED_ORIGINS.some(o => origin === o || origin.endsWith('.netlify.app'));
  const allow = isAllowed ? origin : ALLOWED_ORIGINS[0];

  const CORS = {
    'Access-Control-Allow-Origin': allow,
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, apikey, x-idempotency-key',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };

  if (event.httpMethod === 'OPTIONS') return { statusCode: 200, headers: CORS, body: '' };
  if (event.httpMethod !== 'POST')    return { statusCode: 405, headers: CORS, body: 'Method not allowed' };
  if (!isAllowed) return { statusCode: 403, headers: CORS, body: JSON.stringify({ ok: false, error: 'Origin not allowed' }) };

  // Client IP for rate limit key
  const ip = (event.headers['x-forwarded-for'] || '').split(',')[0].trim()
          || event.headers['x-nf-client-connection-ip'] || 'unknown';

  try {
    const STRIPE_KEY = process.env.STRIPE_SECRET_KEY;
    const SUPABASE_URL = process.env.SUPABASE_URL;
    const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
    if (!STRIPE_KEY) throw new Error('STRIPE_SECRET_KEY not set');

    // ── Rate limit via Supabase (if configured) ──
    if (SUPABASE_URL && SUPABASE_SERVICE_KEY) {
      const rlRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/check_rate_limit`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': SUPABASE_SERVICE_KEY,
          'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
        },
        body: JSON.stringify({ p_key: ip, p_endpoint: 'create-stripe-link', p_max_per_min: RATE_LIMIT_PER_MIN }),
      });
      const allowed = await rlRes.json();
      if (allowed === false) {
        return { statusCode: 429, headers: CORS, body: JSON.stringify({ ok: false, error: `Rate limit exceeded (${RATE_LIMIT_PER_MIN}/min). Try again shortly.` }) };
      }
    }

    const body = JSON.parse(event.body || '{}');
    const {
      name, description = '', price_amount, currency = 'usd', emoji = '',
      product_id, success_url = 'https://teatapler.com/shop.html?checkout=success',
      mode = 'product', interval = 'month', interval_count = 1, trial_days = 0,
      event_id, quantity_adjustable = false, max_quantity = 10,
    } = body;

    // ── Input validation ──
    if (!name || typeof name !== 'string' || name.length > 200) throw new Error('name must be string ≤ 200 chars');
    if (description && (typeof description !== 'string' || description.length > 2000)) throw new Error('description too long');
    const priceNum = Number(price_amount);
    if (!priceNum || isNaN(priceNum) || priceNum <= 0 || priceNum > 100000) throw new Error('price_amount must be 0 < price ≤ 100000');
    if (!['usd','eur','gbp','sgd','aed'].includes(currency)) throw new Error('unsupported currency');
    if (!['product','subscription','event','gift_card'].includes(mode)) throw new Error('invalid mode');
    if (mode === 'subscription' && !['day','week','month','year'].includes(interval)) throw new Error('invalid interval');

    const base = 'https://api.stripe.com/v1';
    const auth = {
      'Authorization': `Bearer ${STRIPE_KEY}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    };
    // Idempotency — client can pass one, else derive stable key
    const idempotencyKey = event.headers['x-idempotency-key']
      || `tt_${mode}_${(product_id||event_id||name).slice(0,40)}_${priceNum}_${currency}`;

    const enc = (obj) => Object.entries(obj)
      .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&');

    const metadata = { mode };
    if (product_id) metadata.supabase_product_id = product_id;
    if (event_id)   metadata.supabase_event_id = event_id;

    // 1. Product
    const prodPayload = { name: `${emoji ? emoji + ' ' : ''}${name}` };
    if (description) prodPayload.description = description;
    Object.entries(metadata).forEach(([k, v]) => { prodPayload[`metadata[${k}]`] = v; });

    const pRes = await fetch(`${base}/products`, {
      method: 'POST',
      headers: { ...auth, 'Idempotency-Key': idempotencyKey + '_prod' },
      body: enc(prodPayload),
    });
    const stripeProduct = await pRes.json();
    if (!pRes.ok) throw new Error(`Stripe product: ${stripeProduct.error?.message}`);

    // 2. Price
    const pricePayload = {
      product: stripeProduct.id,
      unit_amount: String(Math.round(priceNum * 100)),
      currency,
    };
    if (mode === 'subscription') {
      pricePayload['recurring[interval]'] = interval;
      pricePayload['recurring[interval_count]'] = String(interval_count);
    }

    const priceRes = await fetch(`${base}/prices`, {
      method: 'POST',
      headers: { ...auth, 'Idempotency-Key': idempotencyKey + '_price' },
      body: enc(pricePayload),
    });
    const stripePrice = await priceRes.json();
    if (!priceRes.ok) throw new Error(`Stripe price: ${stripePrice.error?.message}`);

    // 3. Payment Link
    const linkPayload = {
      'line_items[0][price]': stripePrice.id,
      'line_items[0][quantity]': '1',
      'after_completion[type]': 'redirect',
      'after_completion[redirect][url]': success_url,
    };
    if (mode === 'subscription' && trial_days > 0 && trial_days <= 90) {
      linkPayload['subscription_data[trial_period_days]'] = String(trial_days);
    }
    if (quantity_adjustable && mode !== 'subscription') {
      linkPayload['line_items[0][adjustable_quantity][enabled]'] = 'true';
      linkPayload['line_items[0][adjustable_quantity][minimum]'] = '1';
      linkPayload['line_items[0][adjustable_quantity][maximum]'] = String(Math.min(max_quantity, 99));
    }
    if (mode === 'event' || mode === 'gift_card') {
      linkPayload['customer_creation'] = 'if_required';
    }
    Object.entries(metadata).forEach(([k, v]) => { linkPayload[`metadata[${k}]`] = v; });

    const linkRes = await fetch(`${base}/payment_links`, {
      method: 'POST',
      headers: { ...auth, 'Idempotency-Key': idempotencyKey + '_link' },
      body: enc(linkPayload),
    });
    const paymentLink = await linkRes.json();
    if (!linkRes.ok) throw new Error(`Stripe payment link: ${paymentLink.error?.message}`);

    // Log success (fire and forget)
    if (SUPABASE_URL && SUPABASE_SERVICE_KEY) {
      fetch(`${SUPABASE_URL}/rest/v1/api_logs`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': SUPABASE_SERVICE_KEY,
          'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
        },
        body: JSON.stringify({
          action: 'create_stripe_link', resource_type: mode, resource_id: paymentLink.id,
          ip_address: ip, success: true,
          metadata: { stripe_product: stripeProduct.id, stripe_price: stripePrice.id },
        }),
      }).catch(() => {});
    }

    return {
      statusCode: 200,
      headers: { ...CORS, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        ok: true, mode,
        payment_link_url: paymentLink.url,
        payment_link_id: paymentLink.id,
        stripe_product_id: stripeProduct.id,
        stripe_price_id: stripePrice.id,
      }),
    };

  } catch (err) {
    if (process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_KEY) {
      fetch(`${process.env.SUPABASE_URL}/rest/v1/api_logs`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': process.env.SUPABASE_SERVICE_KEY,
          'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_KEY}`,
        },
        body: JSON.stringify({
          action: 'create_stripe_link', ip_address: ip, success: false, error_message: err.message,
        }),
      }).catch(() => {});
    }
    return {
      statusCode: 400,
      headers: { ...CORS, 'Content-Type': 'application/json' },
      body: JSON.stringify({ ok: false, error: err.message }),
    };
  }
};
