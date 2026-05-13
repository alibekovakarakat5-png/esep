/**
 * Generate TTS audio for course lessons.
 *
 * Поддерживает два провайдера:
 *   --provider=edge        (по умолчанию, бесплатно, голос ru-RU-DmitryNeural)
 *   --provider=elevenlabs  (требует ELEVENLABS_API_KEY в env)
 *
 * Использование:
 *   node scripts/generate-tts.js --lesson=01 --provider=edge --version=full
 *   node scripts/generate-tts.js --lesson=01 --provider=elevenlabs --version=reel
 *
 * На выходе:
 *   public/audio/lesson-{N}-{version}.mp3   — единый трек
 *   public/audio/lesson-{N}-{version}.json  — длительность сцен в секундах
 */

const fs = require('fs');
const path = require('path');

// ── CLI ────────────────────────────────────────────────────────────────────
const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const [k, v] = a.replace(/^--/, '').split('=');
    return [k, v ?? true];
  })
);

const LESSON = args.lesson || '01';
const PROVIDER = args.provider || 'edge';
const VERSION = args.version || 'full'; // 'full' | 'reel'

const SCENE_FILE = path.join(__dirname, '..', 'scenes', `lesson-${LESSON}.json`);
const OUT_DIR = path.join(__dirname, '..', 'public', 'audio');
const OUT_MP3 = path.join(OUT_DIR, `lesson-${LESSON}-${VERSION}.mp3`);
const OUT_JSON = path.join(OUT_DIR, `lesson-${LESSON}-${VERSION}.json`);

if (!fs.existsSync(SCENE_FILE)) {
  console.error(`Сценарий не найден: ${SCENE_FILE}`);
  process.exit(1);
}

fs.mkdirSync(OUT_DIR, { recursive: true });

const scene = JSON.parse(fs.readFileSync(SCENE_FILE, 'utf8'));
const scenes = scene.scenes?.[VERSION] || [];
if (scenes.length === 0) {
  console.error(`Нет сцен для версии "${VERSION}" в ${SCENE_FILE}`);
  process.exit(1);
}

// ── Provider: Edge TTS ─────────────────────────────────────────────────────
async function generateEdgeTTS() {
  // msedge-tts — бесплатный TTS через Microsoft Edge Cloud
  // https://www.npmjs.com/package/msedge-tts
  const { MsEdgeTTS } = require('msedge-tts');

  const tts = new MsEdgeTTS();
  const voice = scene.voice?.edge || 'ru-RU-DmitryNeural';
  const rate = scene.voice?.edgeRate || '+15%';
  await tts.setMetadata(voice, 'audio-24khz-48kbitrate-mono-mp3');

  const chunks = [];
  const durations = {};

  for (const s of scenes) {
    console.log(`[edge-tts] scene "${s.id}" (${s.text.length} chars)...`);
    const ssml = `<speak version="1.0" xml:lang="ru-RU"><prosody rate="${rate}">${escapeSSML(s.text)}</prosody></speak>`;
    const { audioStream } = await tts.toStream(s.text, { ssml });

    const buf = await streamToBuffer(audioStream);
    chunks.push(buf);

    // Длительность mp3 нужна для синхронизации с Remotion.
    // Берём из заголовков mp3 — приближённо считаем как длительность сценарного бюджета;
    // для точности — Remotion сам перечитает реальную длительность через @remotion/media-utils.
    durations[s.id] = s.duration; // эвристика
  }

  const combined = Buffer.concat(chunks);
  fs.writeFileSync(OUT_MP3, combined);
  fs.writeFileSync(OUT_JSON, JSON.stringify({ provider: 'edge', voice, rate, durations, totalEstimatedSec: scenes.reduce((s, c) => s + c.duration, 0) }, null, 2));
  console.log(`\nOK → ${OUT_MP3}`);
  console.log(`OK → ${OUT_JSON}`);
}

function streamToBuffer(stream) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    stream.on('data', (c) => chunks.push(c));
    stream.on('end', () => resolve(Buffer.concat(chunks)));
    stream.on('error', reject);
  });
}

function escapeSSML(s) {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ── Provider: ElevenLabs ───────────────────────────────────────────────────
async function generateElevenLabs() {
  const apiKey = process.env.ELEVENLABS_API_KEY;
  if (!apiKey) {
    console.error('ELEVENLABS_API_KEY не задан. Установите переменную или используйте --provider=edge');
    process.exit(1);
  }

  const voiceId = scene.voice?.elevenlabsId || '21m00Tcm4TlvDq8ikWAM';
  const charPreset = scene.voice?.elevenlabsCharacter || 'narrator';
  const styles = {
    dramatic:        { stability: 0.3, similarity_boost: 0.8, style: 0.7 },
    narrator:        { stability: 0.5, similarity_boost: 0.75, style: 0.4 },
    expert:          { stability: 0.6, similarity_boost: 0.85, style: 0.3 },
    calm:            { stability: 0.7, similarity_boost: 0.8, style: 0.2 },
    conversational:  { stability: 0.45, similarity_boost: 0.7, style: 0.5 },
  };
  const settings = styles[charPreset] || styles.narrator;

  const chunks = [];
  const durations = {};

  for (const s of scenes) {
    console.log(`[elevenlabs] scene "${s.id}" (${s.text.length} chars)...`);
    const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=mp3_44100_128`, {
      method: 'POST',
      headers: {
        'xi-api-key': apiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        text: s.text,
        model_id: 'eleven_multilingual_v2',
        voice_settings: settings,
      }),
    });
    if (!res.ok) {
      throw new Error(`ElevenLabs API error: ${res.status} ${await res.text()}`);
    }
    const buf = Buffer.from(await res.arrayBuffer());
    chunks.push(buf);
    durations[s.id] = s.duration;
  }

  fs.writeFileSync(OUT_MP3, Buffer.concat(chunks));
  fs.writeFileSync(OUT_JSON, JSON.stringify({ provider: 'elevenlabs', voiceId, character: charPreset, durations, totalEstimatedSec: scenes.reduce((s, c) => s + c.duration, 0) }, null, 2));
  console.log(`\nOK → ${OUT_MP3}`);
  console.log(`OK → ${OUT_JSON}`);
}

// ── Main ───────────────────────────────────────────────────────────────────
(async () => {
  console.log(`Generating TTS:`);
  console.log(`  lesson:   ${LESSON}`);
  console.log(`  version:  ${VERSION}`);
  console.log(`  provider: ${PROVIDER}`);
  console.log(`  scenes:   ${scenes.length}\n`);

  if (PROVIDER === 'edge') {
    await generateEdgeTTS();
  } else if (PROVIDER === 'elevenlabs') {
    await generateElevenLabs();
  } else {
    console.error(`Неизвестный провайдер: ${PROVIDER}`);
    process.exit(1);
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
