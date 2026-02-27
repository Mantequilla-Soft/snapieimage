require('dotenv').config();
const express = require('express');
const multer = require('multer');
const sharp = require('sharp');
const helmet = require('helmet');
const crypto = require('crypto');
const path = require('path');
const fs = require('fs');

// Configuration
const config = {
  port: parseInt(process.env.PORT) || 3000,
  apiKey: process.env.API_KEY,
  uploadDir: process.env.UPLOAD_DIR || './uploads',
  baseUrl: process.env.BASE_URL || `http://localhost:${parseInt(process.env.PORT) || 3000}`
};

// Validate configuration on startup
if (!config.apiKey || config.apiKey.length < 32) {
  console.error('ERROR: API_KEY must be set in .env file and be at least 32 characters long.');
  console.error('Generate a secure key with: node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'hex\'))"');
  process.exit(1);
}

// Ensure upload directory exists
if (!fs.existsSync(config.uploadDir)) {
  fs.mkdirSync(config.uploadDir, { recursive: true });
  console.log(`Created upload directory: ${config.uploadDir}`);
}

// Initialize Express app
const app = express();

// Security middleware
app.disable('x-powered-by');
app.use(helmet());

// Serve static images (for standalone use without nginx)
app.use('/images', express.static(config.uploadDir));

// API Key Authentication Middleware
function authenticateAPIKey(req, res, next) {
  const authHeader = req.headers.authorization;
  
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ 
      error: 'Missing or invalid authorization header',
      message: 'Authorization header must be in format: Bearer YOUR_API_KEY'
    });
  }
  
  const token = authHeader.substring(7);
  
  // Constant-time comparison to prevent timing attacks
  const expectedKey = config.apiKey;
  if (token.length !== expectedKey.length || 
      !crypto.timingSafeEqual(Buffer.from(token), Buffer.from(expectedKey))) {
    return res.status(403).json({ error: 'Invalid API key' });
  }
  
  next();
}

// Multer configuration for file uploads
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024,  // 10MB max
    files: 1
  },
  fileFilter: (req, file, cb) => {
    const allowedMimes = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
    if (allowedMimes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Invalid file type. Only JPEG, PNG, WebP, and GIF images are allowed.'));
    }
  }
});

// Generate secure filename
function generateSafeFilename() {
  const timestamp = Date.now();
  const randomHash = crypto.randomBytes(8).toString('hex');
  return `${timestamp}-${randomHash}.webp`;
}

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// Upload endpoint
app.post('/upload', authenticateAPIKey, (req, res) => {
  upload.single('image')(req, res, async (err) => {
    // Handle Multer errors
    if (err instanceof multer.MulterError) {
      if (err.code === 'LIMIT_FILE_SIZE') {
        return res.status(413).json({ error: 'File too large. Maximum size is 10MB.' });
      }
      return res.status(400).json({ error: err.message });
    }
    
    if (err) {
      return res.status(400).json({ error: err.message });
    }
    
    // Validate file was uploaded
    if (!req.file) {
      return res.status(400).json({ error: 'No image file provided. Use multipart/form-data with field name "image".' });
    }
    
    try {
      // Validate image with Sharp (will throw on invalid images)
      const metadata = await sharp(req.file.buffer).metadata();
      const isGif = metadata.format === 'gif';
      console.log(`Processing ${metadata.format} image: ${metadata.width}x${metadata.height}${isGif ? ' (animated)' : ''}`);
      
      // Generate safe filename
      const filename = generateSafeFilename();
      const outputPath = path.resolve(config.uploadDir, filename);
      
      // Verify path doesn't escape upload directory
      if (!outputPath.startsWith(path.resolve(config.uploadDir))) {
        throw new Error('Invalid file path');
      }
      
      // Process and optimize image
      // Preserve animation for GIFs
      const webpOptions = { quality: 80, effort: 4 };
      if (isGif) {
        webpOptions.animated = true;
      }
      
      await sharp(req.file.buffer, isGif ? { animated: true } : {})
        .rotate()  // Auto-rotate based on EXIF orientation
        .webp(webpOptions)
        .toFile(outputPath);
      
      const imageUrl = `${config.baseUrl}/images/${filename}`;
      
      console.log(`Image uploaded successfully: ${filename}`);
      
      res.status(201).json({
        success: true,
        url: imageUrl,
        filename: filename,
        originalFormat: metadata.format,
        size: {
          width: metadata.width,
          height: metadata.height
        }
      });
      
    } catch (error) {
      console.error('Image processing error:', error);
      
      // Handle specific error cases
      if (error.code === 'ENOSPC') {
        return res.status(507).json({ error: 'Insufficient storage space on server.' });
      }
      
      if (error.message.includes('Input buffer')) {
        return res.status(400).json({ error: 'Invalid or corrupted image file.' });
      }
      
      res.status(500).json({ 
        error: 'Failed to process image',
        message: error.message 
      });
    }
  });
});

// Global error handler
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

// Uncaught exception handler (last resort for reliability)
process.on('uncaughtException', (err) => {
  console.error('FATAL: Uncaught exception:', err);
  process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('FATAL: Unhandled promise rejection:', reason);
  process.exit(1);
});

// Start server
app.listen(config.port, () => {
  console.log('=================================');
  console.log('Image Server Started');
  console.log('=================================');
  console.log(`Port: ${config.port}`);
  console.log(`Upload directory: ${path.resolve(config.uploadDir)}`);
  console.log(`Base URL: ${config.baseUrl}`);
  console.log('=================================');
  console.log('Endpoints:');
  console.log(`  POST /upload  - Upload and optimize images`);
  console.log(`  GET  /health  - Health check`);
  console.log('=================================');
});
