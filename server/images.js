const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const multer = require('multer');
const { loadConfig, saveConfig } = require('./config');

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

      // Scale original to max display size for better performance
      // This reduces memory usage when Chromium loads images
      const maxDisplaySize = cfg.maxDisplayLongSide || 1920;
      const needsScaling = longSide > maxDisplaySize;

      // Determine output format based on original file extension
      const ext = path.extname(file.originalname).toLowerCase();
      const isJpeg = ['.jpg', '.jpeg'].includes(ext);
      const isPng = ext === '.png';
      const isWebP = ext === '.webp';

      // Build processing pipeline
      let pipeline = sharp(file.path).rotate(); // Auto-rotate based on EXIF orientation

      if (needsScaling) {
        pipeline = pipeline.resize(maxDisplaySize, maxDisplaySize, {
          fit: 'inside',
          withoutEnlargement: true,
        });
        
        // Apply format-specific quality settings only when scaling
        // This optimizes the output while preserving the original format
        if (isJpeg) {
          pipeline = pipeline.jpeg({ quality: 92, mozjpeg: true });
        } else if (isPng) {
          pipeline = pipeline.png({ quality: 92, compressionLevel: 9 });
        } else if (isWebP) {
          pipeline = pipeline.webp({ quality: 92 });
        }
        // For other formats, Sharp will preserve the format automatically
      }
      // If not scaling, just rotate and preserve original format/quality

      await pipeline.toFile(target);
      fs.unlinkSync(file.path); // Remove temp file

      // Create thumbnail
      await sharp(target)
        .resize(320, 320, { fit: 'cover', position: 'centre' })
        .toFile(thumb);

      // Add new image to the order array
      // Reload config to get latest imageOrder (in case it was modified)
      const currentCfg = loadConfig();
      if (!currentCfg.imageOrder) {
        currentCfg.imageOrder = [];
      }
      if (!currentCfg.imageOrder.includes(file.originalname)) {
        currentCfg.imageOrder.push(file.originalname);
        saveConfig(currentCfg);
      }

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
  const cfg = loadConfig();
  const files = fs.readdirSync(ORIGINALS).filter(f => !f.startsWith('.'));

  // Get stored image order from config, or use alphabetical as fallback
  const imageOrder = cfg.imageOrder || [];

  // Sort files according to stored order, with new files appended at the end
  const sortedFiles = files.sort((a, b) => {
    const indexA = imageOrder.indexOf(a);
    const indexB = imageOrder.indexOf(b);

    // If both are in the order array, sort by their position
    if (indexA !== -1 && indexB !== -1) {
      return indexA - indexB;
    }
    // If only A is in the order array, A comes first
    if (indexA !== -1) return -1;
    // If only B is in the order array, B comes first
    if (indexB !== -1) return 1;
    // If neither is in the order array, sort alphabetically
    return a.localeCompare(b, 'sv');
  });

  return sortedFiles.map(f => ({
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

    // Remove from image order if it exists
    const cfg = loadConfig();
    if (cfg.imageOrder) {
      cfg.imageOrder = cfg.imageOrder.filter(id => id !== f);
      saveConfig(cfg);
    }

    // Broadcast image list update after successful deletion
    broadcastImageList();

    res.json({ ok: true });
  } catch (err) {
    console.error('Delete failed:', err);
    res.status(500).json({ ok: false, error: err.message });
  }
}

function updateImageOrder(req, res) {
  try {
    const { order } = req.body;
    if (!Array.isArray(order)) {
      return res
        .status(400)
        .json({ ok: false, error: 'Order must be an array' });
    }

    const cfg = loadConfig();
    cfg.imageOrder = order;
    saveConfig(cfg);

    // Broadcast image list update after successful reordering
    broadcastImageList();

    res.json({ ok: true });
  } catch (err) {
    console.error('Update order failed:', err);
    res.status(500).json({ ok: false, error: err.message });
  }
}

module.exports = {
  upload,
  handleUpload,
  listImages,
  listImagesSync,
  deleteImage,
  updateImageOrder,
  setBroadcastCallback,
};
