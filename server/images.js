const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const multer = require('multer');
const { loadConfig } = require('./config');

const IMAGE_ROOT = path.join(__dirname, '../public/images');
const ORIGINALS = path.join(IMAGE_ROOT, 'originals');
const THUMBS = path.join(IMAGE_ROOT, 'thumbs');

fs.mkdirSync(ORIGINALS, { recursive: true });
fs.mkdirSync(THUMBS, { recursive: true });

const upload = multer({ dest: '/tmp' });

let broadcastCallback = null;

function setBroadcastCallback(callback) {
  broadcastCallback = callback;
}

function broadcastImageList() {
  if (broadcastCallback) {
    const imageList = listImagesSync();
    broadcastCallback({ type: 'images-updated', images: imageList });
  }
}

async function handleUpload(req, res) {
  const cfg = loadConfig();
  const results = [];

  for (const file of req.files) {
    try {
      const meta = await sharp(file.path).metadata();
      const longSide = Math.max(meta.width, meta.height);

      if (longSide < cfg.minImageLongSide) {
        fs.unlinkSync(file.path);
        results.push({
          file: file.originalname,
          ok: false,
          error: `För låg upplösning (krav ${cfg.minImageLongSide}px)`,
        });
        continue;
      }

      const target = path.join(ORIGINALS, file.originalname);
      const thumb = path.join(THUMBS, file.originalname);

      fs.renameSync(file.path, target);

      await sharp(target)
        .resize(320, 320, { fit: 'cover', position: 'centre' })
        .toFile(thumb);

      results.push({ file: file.originalname, ok: true });
    } catch (err) {
      results.push({ file: file.originalname, ok: false, error: err.message });
    }
  }

  // Broadcast image list update if any uploads succeeded
  if (results.some(r => r.ok)) {
    broadcastImageList();
  }

  res.json(results);
}

function listImagesSync() {
  const files = fs
    .readdirSync(ORIGINALS)
    .filter(f => !f.startsWith('.'))
    .sort((a, b) => a.localeCompare(b, 'sv'));
  return files.map(f => ({
    id: f,
    original: `/images/originals/${f}`,
    thumb: `/images/thumbs/${f}`,
  }));
}

function listImages(req, res) {
  res.json(listImagesSync());
}

function deleteImage(req, res) {
  const f = path.basename(req.params.id);

  const orig = path.join(ORIGINALS, f);
  const thumb = path.join(THUMBS, f);

  try {
    if (fs.existsSync(orig)) fs.unlinkSync(orig);
    if (fs.existsSync(thumb)) fs.unlinkSync(thumb);

    // Broadcast image list update after successful deletion
    broadcastImageList();

    res.json({ ok: true });
  } catch (err) {
    console.error('Delete failed:', err);
    res.status(500).json({ ok: false, error: err.message });
  }
}

module.exports = {
  upload,
  handleUpload,
  listImages,
  deleteImage,
  setBroadcastCallback,
};
