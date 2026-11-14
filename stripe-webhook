// netlify/functions/stripe-webhook.js
// Receives Stripe events and syncs them to Supabase.
// Setup:
//   1. Netlify env vars: STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, SUPABASE_URL, SUPABASE_SERVICE_KEY
//   2. Stripe Dashboard > Developers > Webhooks > Add endpoint:
//        URL: https://YOUR-NETLIFY-SITE.netlify.app/.netlify/functions/stripe-webhook
//        Events: checkout.session.completed, invoice.paid, invoice.payment_failed,
//                customer.subscription.created, customer.subscription.updated,
//                customer.subscription.deleted
//   3. Copy the "Signing secret" (whsec_...) into STRIPE_WEBHOOK_SECRET.

const crypto = require('crypto');

function verifyStripeSignature(payload, header, secret) {
  if (!header || !secret) return false;
  const items = header.split(',').reduce((acc, kv) => {
    const [k, v] = kv.split('='); acc[k] = v; return acc;
  }, {});
  if (!items.t || !items.v1) return false;
  const signed = `${items.t}.${payload}`;
  const expected = crypto.createHmac('sha256', secret).update(signed).digest('hex');
  // Timing-safe compare
  try {
    return crypto.timingSafeEqual(Buffer.from(items.v1, 'hex'), Buffer.from(expected, 'hex'));
  } catch { return false; }
}

async function sbInsert(table, body) {
  return fetch(`${process.env.SUPABASE_URL}/rest/v1/${table}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'apikey': process.env.SUPABASE_SERVICE_KEY,
      'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_KEY}`,
      'Prefer': 'resolution=merge-duplicates',
    },
    body: JSON.stringify(body),
  });
}

async function sbUpdate(table, filter, body) {
  return fetch(`${process.env.SUPABASE_URL}/rest/v1/${table}?${filter}`, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      'apikey': process.env.SUPABASE_SERVICE_KEY,
      'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_KEY}`,
    },
    body: JSON.stringify(body),
  });
}

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') return { statusCode: 405, body: 'Method not allowed' };

  const sig = event.headers['stripe-signature'];
  const secret = process.env.STRIPE_WEBHOOK_SECRET;
  const payload = event.body;

  if (!verifyStripeSignature(payload, sig, secret)) {
    return { statusCode: 400, body: 'Invalid signature' };
  }

  let stripeEvent;
  try { stripeEvent = JSON.parse(payload); }
  catch { return { statusCode: 400, body: 'Invalid JSON' }; }

  // Idempotency: skip if already processed
  try {
    const dupeCheck = await fetch(
      `${process.env.SUPABASE_URL}/rest/v1/stripe_events?id=eq.${stripeEvent.id}&select=id`,
      { headers: {
        'apikey': process.env.SUPABASE_SERVICE_KEY,
        'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_KEY}`,
      }},
    );
    const existing = await dupeCheck.json();
    if (Array.isArray(existing) && existing.length > 0) {
      return { statusCode: 200, body: JSON.stringify({ received: true, duplicate: true }) };
    }
  } catch {}

  // Log event
  await sbInsert('stripe_events', {
    id: stripeEvent.id,
    type: stripeEvent.type,
    payload: stripeEvent.data?.object || {},
  });

  // Dispatch
  const obj = stripeEvent.data?.object || {};
  const meta = obj.metadata || {};

  try {
    switch (stripeEvent.type) {
      case 'checkout.session.completed': {
        if (meta.mode === 'event' && meta.supabase_event_id) {
          // Create event ticket + increment count
          await sbInsert('event_tickets', {
            event_id: meta.supabase_event_id,
            email: obj.customer_details?.email,
            name: obj.customer_details?.name,
            amount_paid: (obj.amount_total || 0) / 100,
            stripe_session_id: obj.id,
            payment_status: 'paid',
          });
          // RPC increment
          await fetch(`${process.env.SUPABASE_URL}/rest/v1/rpc/increment_rsvp_count`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'apikey': process.env.SUPABASE_SERVICE_KEY,
              'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_KEY}`,
            },
            body: JSON.stringify({ event_id: meta.supabase_event_id }),
          });
        }
        if (meta.mode === 'gift_card') {
          // Mark the pending gift card as active
          await sbUpdate('gift_cards',
            `stripe_session_id=eq.${obj.id}`,
            { status: 'active', stripe_session_id: obj.id },
          );
        }
        break;
      }
      case 'customer.subscription.created':
      case 'customer.subscription.updated': {
        // Could sync to a subscribers table if you add one
        break;
      }
      case 'invoice.payment_failed': {
        // Could email the customer / flag in admin
        break;
      }
    }
  } catch (err) {
    console.error('Webhook dispatch error:', err);
    // Still return 200 — Stripe will retry on 5xx
  }

  return { statusCode: 200, body: JSON.stringify({ received: true }) };
};
