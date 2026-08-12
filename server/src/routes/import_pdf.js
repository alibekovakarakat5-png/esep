const router = require('express').Router();
const multer = require('multer');

const { parseKaspiPdfBuffer } = require('../services/kaspi_pdf');

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 15 * 1024 * 1024 }, // 15 MB — годовая выписка ~250 КБ
});

// POST /api/import/kaspi-pdf — PDF-выписка Kaspi Gold → операции.
// Разбор серверный: на клиенте (Flutter web) нет разбора PDF, а pdf-parse
// на Node справляется с родным форматом «Справка + Выписка» Kaspi.
router.post('/kaspi-pdf', upload.single('file'), async (req, res) => {
  try {
    if (!req.file || !req.file.buffer || !req.file.buffer.length) {
      return res.status(400).json({ error: 'Приложите PDF-файл (multipart-поле file)' });
    }
    const { rows, warnings } = await parseKaspiPdfBuffer(req.file.buffer);
    res.json({ rows, warnings, count: rows.length });
  } catch (err) {
    console.error('POST /import/kaspi-pdf error:', err.message);
    res.status(422).json({
      error: 'Не удалось разобрать PDF. Проверьте, что это выписка Kaspi (Справка + Выписка).',
    });
  }
});

module.exports = router;
