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
          error: `För låg upplösning (krav ${cfg.minImageLongSide}px)`
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

  res.json(results);
}

function listImages(req, res) {
  const files = fs.readdirSync(ORIGINALS).filter(f => !f.startsWith('.'));
  res.json(
    files.map(f => ({
      id: f,
      original: `/images/originals/${f}`,
      thumb: `/images/thumbs/${f}`
    }))
  );
}

function deleteImage(req,res){
  const f = req.params.id;
  fs.unlinkSync(path.join(ORIGINALS,f));
  fs.unlinkSync(path.join(THUMBS,f));
  res.json({ok:true});
}

module.exports = { upload, handleUpload, listImages };
