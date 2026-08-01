// netlify/functions/create-stripe-link.js
// Set env var in Netlify: Site settings > Environment variables > STRIPE_SECRET_KEY = sk_live_...

exports.handler = async (event) => {
  const CORS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, apikey',
  };

  if (event.httpMethod === 'OPTIONS') return { statusCode: 200, headers: CORS, body: '' };
  if (event.httpMethod !== 'POST') return { statusCode: 405, body: 'Method not allowed' };

  try {
    const STRIPE_KEY = process.env.STRIPE_SECRET_KEY;
    if (!STRIPE_KEY) throw new Error('STRIPE_SECRET_KEY not set in Netlify environment variables');

    const { product_id, name, description = '', price_amount, currency = 'usd', emoji = '',
            success_url = 'https://teatapler.com/shop.html?checkout=success' } = JSON.parse(event.body);

    if (!name) throw new Error('name required');
    if (!price_amount || isNaN(price_amount)) throw new Error('price_amount required');

    const base = 'https://api.stripe.com/v1';
    const auth = { 'Authorization': `Bearer ${STRIPE_KEY}`, 'Content-Type': 'application/x-www-form-urlencoded' };
    const enc = (obj) => Object.entries(obj).map(([k,v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&');

    // 1. Create Stripe Product
    const pRes  = await fetch(`${base}/products`, { method:'POST', headers:auth, body:enc({ name:`${emoji?emoji+' ':''}${name}`, ...(description?{description}:{}), ...(product_id?{'metadata[supabase_id]':product_id}:{}) }) });
    const prod  = await pRes.json();
    if (!pRes.ok) throw new Error(`Stripe product: ${prod.error?.message}`);

    // 2. Create Stripe Price
    const prRes  = await fetch(`${base}/prices`, { method:'POST', headers:auth, body:enc({ product:prod.id, unit_amount:String(Math.round(Number(price_amount)*100)), currency }) });
    const price  = await prRes.json();
    if (!prRes.ok) throw new Error(`Stripe price: ${price.error?.message}`);

    // 3. Create Payment Link
    const lRes  = await fetch(`${base}/payment_links`, { method:'POST', headers:auth, body:enc({ 'line_items[0][price]':price.id, 'line_items[0][quantity]':'1', 'after_completion[type]':'redirect', 'after_completion[redirect][url]':success_url }) });
    const link  = await lRes.json();
    if (!lRes.ok) throw new Error(`Stripe payment link: ${link.error?.message}`);

    return { statusCode:200, headers:{...CORS,'Content-Type':'application/json'},
      body: JSON.stringify({ ok:true, payment_link_url:link.url, payment_link_id:link.id, stripe_product_id:prod.id, stripe_price_id:price.id }) };

  } catch (err) {
    return { statusCode:400, headers:{...CORS,'Content-Type':'application/json'}, body:JSON.stringify({ ok:false, error:err.message }) };
  }
};
