// ── Seed platform knowledge in DB ────────────────────────────────────────────
// Загружает справочник по платформе Esep в knowledge_source / knowledge_chunk.
// Запускается при старте сервера. Идемпотентен — пересчитывает только если
// контент изменился.

const { ESEP_PLATFORM_DOCS } = require('../data/esep_platform_knowledge');
const { indexSource } = require('../services/knowledge_indexer');

const BASE_URL = 'esep://platform/';

async function seedEsepPlatformKnowledge() {
  let totalIndexed = 0;
  let totalSkipped = 0;
  for (const doc of ESEP_PLATFORM_DOCS) {
    try {
      const res = await indexSource({
        url: BASE_URL + doc.slug,
        title: doc.title,
        sourceType: 'esep_platform',
        trustWeight: 1.0, // мы доверяем себе на 100%
        rawContent: doc.body,
        metadata: {
          slug: doc.slug,
          screen_anchor: doc.anchor || null,
        },
        // Чанк один — и так короткий
        chunks: [{
          text: `${doc.title}\n\n${doc.body}`,
          audienceHint: doc.audience || 'all',
          complexity:   doc.complexity || 'simple',
          anchor:       doc.anchor || null,
        }],
      });
      if (res.contentChanged) totalIndexed++;
      else totalSkipped++;
    } catch (err) {
      console.error(`[seed platform] '${doc.slug}' failed:`, err.message);
    }
  }
  console.log(`✅  Esep platform knowledge: indexed=${totalIndexed}, unchanged=${totalSkipped}`);
}

module.exports = { seedEsepPlatformKnowledge };
