// ============================================================================
//  Supabase Edge Function: `ocr`
//
//  Fallback OCR engine for platforms where ML Kit is unavailable
//  (Web / Windows / macOS / Linux). Uses Google Cloud Vision TEXT_DETECTION.
//
//  Deploy:
//    supabase functions deploy ocr
//    supabase secrets set GOOGLE_VISION_API_KEY=xxxx
// ============================================================================

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405);

  try {
    const authorization = req.headers.get('Authorization') ?? '';
    if (!authorization) return json({ error: 'missing authorization' }, 401);

    // Verify the caller is a signed-in user of this project.
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authorization } } },
    );
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) return json({ error: 'unauthorized' }, 401);

    const payload = await req.json().catch(() => null);
    const image = payload?.image as string | undefined;
    const language = (payload?.language as string | undefined) ?? 'ja';
    if (!image) return json({ error: 'image (base64) is required' }, 400);

    const apiKey = Deno.env.get('GOOGLE_VISION_API_KEY');
    if (!apiKey) return json({ error: 'GOOGLE_VISION_API_KEY is not set' }, 500);

    const visionResponse = await fetch(
      `https://vision.googleapis.com/v1/images:annotate?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          requests: [
            {
              image: { content: image },
              features: [{ type: 'TEXT_DETECTION', maxResults: 1 }],
              imageContext: { languageHints: [language, 'en'] },
            },
          ],
        }),
      },
    );

    const visionJson = await visionResponse.json();
    if (!visionResponse.ok) {
      return json(
        { error: visionJson?.error?.message ?? 'vision request failed' },
        502,
      );
    }

    const text: string =
      visionJson?.responses?.[0]?.fullTextAnnotation?.text ?? '';

    return json({ text, engine: 'google-vision', language });
  } catch (error) {
    return json({ error: String(error) }, 500);
  }
});
