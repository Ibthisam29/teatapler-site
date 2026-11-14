// netlify/functions/create-stripe-link.js
// Replace the existing file with THIS version — adds subscriptions, event tickets, gift cards.
// Netlify env var required: STRIPE_SECRET_KEY = sk_live_... (or sk_test_...)

exports.handler = async (event) => {
  const CORS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, apikey',
  };
  if (event.httpMethod === 'OPTIONS') return { statusCode: 200, headers: CORS, body: '' };
  if (event.httpMethod !== 'POST')    return { statusCode: 405, body: 'Method not allowed' };

  try {
    const STRIPE_KEY = process.env.STRIPE_SECRET_KEY;
    if (!STRIPE_KEY) throw new Error('STRIPE_SECRET_KEY not set in Netlify environment variables');

    const body = JSON.parse(event.body || '{}');
    const {
      // common
      name,
      description = '',
      price_amount,
      currency = 'usd',
      emoji = '',
      product_id,
      success_url = 'https://teatapler.com/shop.html?checkout=success',

      // mode: 'product' (default), 'subscription', 'event', 'gift_card'
      mode = 'product',

      // subscription
      interval = 'month',          // 'month' | 'year'
      interval_count = 1,          // 1 month, 1 year, etc.
      trial_days = 0,

      // event ticketing
      event_id,
      event_date,
      quantity_adjustable = false, // allow quantity selection on checkout
      max_quantity = 10,
    } = body;

    if (!name) throw new Error('name is required');
    if (!price_amount || isNaN(price_amount)) throw new Error('price_amount must be a number');

    const base = 'https://api.stripe.com/v1';
    const auth = {
      'Authorization': `Bearer ${STRIPE_KEY}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    };
    const enc = (obj) => Object.entries(obj)
      .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&');

    // Build metadata for all modes
    const metadata = {};
    if (product_id) metadata.supabase_product_id = product_id;
    if (event_id)   metadata.supabase_event_id = event_id;
    metadata.mode = mode;

    // ── 1. Create Stripe Product ──────────────────────────────────────
    const prodPayload = {
      name: `${emoji ? emoji + ' ' : ''}${name}`,
      ...(description ? { description } : {}),
    };
    Object.entries(metadata).forEach(([k, v]) => { prodPayload[`metadata[${k}]`] = v; });

    const pRes = await fetch(`${base}/products`, { method: 'POST', headers: auth, body: enc(prodPayload) });
    const stripeProduct = await pRes.json();
    if (!pRes.ok) throw new Error(`Stripe product: ${stripeProduct.error?.message}`);

    // ── 2. Create Stripe Price ────────────────────────────────────────
    const pricePayload = {
      product: stripeProduct.id,
      unit_amount: String(Math.round(Number(price_amount) * 100)),
      currency,
    };
    if (mode === 'subscription') {
      pricePayload['recurring[interval]'] = interval;
      pricePayload['recurring[interval_count]'] = String(interval_count);
    }

    const priceRes = await fetch(`${base}/prices`, { method: 'POST', headers: auth, body: enc(pricePayload) });
    const stripePrice = await priceRes.json();
    if (!priceRes.ok) throw new Error(`Stripe price: ${stripePrice.error?.message}`);

    // ── 3. Create Payment Link ────────────────────────────────────────
    const linkPayload = {
      'line_items[0][price]': stripePrice.id,
      'line_items[0][quantity]': '1',
      'after_completion[type]': 'redirect',
      'after_completion[redirect][url]': success_url,
    };

    if (mode === 'subscription' && trial_days > 0) {
      linkPayload['subscription_data[trial_period_days]'] = String(trial_days);
    }

    if (quantity_adjustable && mode !== 'subscription') {
      linkPayload['line_items[0][adjustable_quantity][enabled]'] = 'true';
      linkPayload['line_items[0][adjustable_quantity][minimum]'] = '1';
      linkPayload['line_items[0][adjustable_quantity][maximum]'] = String(max_quantity);
    }

    // Collect email + name for event tickets and gift cards
    if (mode === 'event' || mode === 'gift_card') {
      linkPayload['customer_creation'] = 'if_required';
    }

    // Pass metadata to payment link too so Stripe webhooks carry it
    Object.entries(metadata).forEach(([k, v]) => {
      linkPayload[`metadata[${k}]`] = v;
    });

    const linkRes = await fetch(`${base}/payment_links`, { method: 'POST', headers: auth, body: enc(linkPayload) });
    const paymentLink = await linkRes.json();
    if (!linkRes.ok) throw new Error(`Stripe payment link: ${paymentLink.error?.message}`);

    return {
      statusCode: 200,
      headers: { ...CORS, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        ok: true,
        mode,
        payment_link_url: paymentLink.url,
        payment_link_id:  paymentLink.id,
        stripe_product_id: stripeProduct.id,
        stripe_price_id:  stripePrice.id,
      }),
    };

  } catch (err) {
    return {
      statusCode: 400,
      headers: { ...CORS, 'Content-Type': 'application/json' },
      body: JSON.stringify({ ok: false, error: err.message }),
    };
  }
};
