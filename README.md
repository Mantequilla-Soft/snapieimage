# Image Server

A simple, reliable Node.js image upload and optimization server. Built as a fallback service for production use — accepts image uploads via API key authentication, converts to WebP format, strips metadata, and returns URLs for optimized images.

## Features

- **API Key Authentication**: Secure Bearer token authentication
- **Automatic WebP Conversion**: All uploads optimized to WebP (quality 80)
- **Metadata Stripping**: Removes EXIF data while preserving visual quality
- **EXIF Orientation Handling**: Auto-rotates images based on EXIF orientation
- **Multiple Format Support**: Accepts JPEG, PNG, WebP, and GIF
- **File Size Limits**: 10MB maximum upload size
- **Configurable**: Port, storage directory, and base URL via environment variables
- **Production-Ready**: Helmet security headers, explicit error handling, health checks

## Quick Start

### Development / Testing (Standalone)

For local development or testing without nginx:

#### 1. Install Dependencies

```bash
npm install
```

#### 2. Configure Environment

Copy the example environment file and generate a secure API key:

```bash
cp .env.example .env
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

Edit `.env` and paste your generated API key:

```env
PORT=3000
API_KEY=<paste_your_generated_key_here>
UPLOAD_DIR=./uploads
BASE_URL=http://localhost:3000
```

#### 3. Start the Server

```bash
npm start
```

The server serves images directly at `/images/*` for standalone use (no nginx needed).

---

### Production Deployment

#### Automated Installation (Recommended)

Run the interactive install script that will:
- ✅ Detect available ports
- ✅ Configure your domain
- ✅ Generate secure API key
- ✅ Create `.env` file with production settings
- ✅ Install nginx configuration
- ✅ Set up systemd service
- ✅ Enable and start services
- ✅ Optionally install SSL certificate
- ✅ Save installation details to `installation-info.txt`

```bash
./install.sh
```

Follow the prompts and the script handles everything! After installation, your API key and configuration will be saved in `installation-info.txt`.

#### Manual Production Installation

If you prefer to set up manually or need custom configuration:

##### 1. Install Dependencies

```bash
npm install --production
```

##### 2. Configure Environment

Generate a secure API key:

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

Create `.env` file with production settings:

```env
PORT=3000
API_KEY=<paste_your_generated_key_here>
UPLOAD_DIR=/path/to/your/project/uploads
BASE_URL=https://images.yourdomain.com
```

##### 3. Set up nginx (see nginx section below)

##### 4. Set up systemd service (see systemd section below)

##### 5. Install SSL certificate with certbot (see SSL section below)

## API Usage

### Upload an Image

**Endpoint**: `POST /upload`

**Authentication**: Bearer token in `Authorization` header

**Request**:
```bash
curl -X POST \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -F "image=@path/to/your/image.jpg" \
  http://localhost:3000/upload
```

**Response** (201 Created):
```json
{
  "success": true,
  "url": "http://localhost:3000/images/1709020800000-a1b2c3d4e5f6g7h8.webp",
  "filename": "1709020800000-a1b2c3d4e5f6g7h8.webp",
  "originalFormat": "jpeg",
  "size": {
    "width": 1920,
    "height": 1080
  }
}
```

**Error Responses**:
- `400 Bad Request`: Invalid file type, no file provided, or corrupted image
- `401 Unauthorized`: Missing authorization header
- `403 Forbidden`: Invalid API key
- `413 Payload Too Large`: File exceeds 10MB
- `500 Internal Server Error`: Image processing failure
- `507 Insufficient Storage`: Disk full

### Health Check

**Endpoint**: `GET /health`

**Response**:
```json
{
  "status": "ok",
  "timestamp": "2026-02-26T12:34:56.789Z",
  "uptime": 3600.5
}
```

## Configuration Details

### Nginx Configuration (Production Only)

**Note**: If you used `./install.sh`, this is already configured for you.

For production, nginx:
1. Reverse proxies the upload endpoint to the Node.js service
2. Serves optimized images as static files (better performance than Node.js)
3. Handles SSL/TLS termination

**Manual nginx config** (`/etc/nginx/sites-available/images.yourdomain.com`):

```nginx
server {
    listen 80;
    server_name images.yourdomain.com;
    
    # Maximum upload size (must match or exceed Node.js limit)
    client_max_body_size 10M;
    
    # Upload endpoint - proxy to Node.js
    location /upload {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # Timeout for large uploads
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
    }
    
    # Health check endpoint
    location /health {
        proxy_pass http://localhost:3000;
        access_log off;
    }
    
    # Static image serving
    location /images/ {
        alias /path/to/your/uploads/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
}
```

**Enable the site**:
```bash
sudo ln -s /etc/nginx/sites-available/images.yourdomain.com /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### SSL with Let's Encrypt (Recommended)

**Note**: If you used `./install.sh`, you were prompted to install SSL automatically.

To install or renew SSL certificate manually:

```bash
sudo certbot --nginx -d images.yourdomain.com
```

### Process Manager (systemd)

**Note**: If you used `./install.sh`, the service is already created and running.

To create the systemd service manually, create `/etc/systemd/system/image-server.service`:

```ini
[Unit]
Description=Image Upload and Optimization Server
After=network.target

[Service]
Type=simple
User=your-username
WorkingDirectory=/path/to/image-server
Environment="NODE_ENV=production"
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

**Enable and start**:
```bash
sudo systemctl daemon-reload
sudo systemctl enable image-server
sudo systemctl start image-server
sudo systemctl status image-server
```

## Architecture

### Production Architecture (with nginx)

```
Client Upload Request
       ↓
  [nginx :80/443]
       ↓
  POST /upload → [Node.js :3000]
                      ↓
                 1. Authenticate API key
                 2. Validate image
                 3. Convert to WebP
                 4. Strip metadata
                 5. Save to filesystem
                      ↓
                 Returns URL
       ↓
Client Access Image
       ↓
  [nginx :80/443]
       ↓
  GET /images/xxx.webp → [nginx serves static file]
```

### Standalone Architecture (development)

```
Client Request
       ↓
  [Node.js :3000]
       ↓
  POST /upload → Process & Save
  GET /images/* → Serve static files
```

## File Storage

Images are stored with randomized filenames to prevent:
- Filename collisions
- Path traversal attacks
- Predictable URLs

**Format**: `<timestamp>-<random_hash>.webp`
**Example**: `1709020800000-a1b2c3d4e5f6g7h8.webp`

## Security Considerations

- **API Key**: 32+ character random hex string (use the generator command)
- **Bearer Token**: Constant-time comparison prevents timing attacks
- **File Validation**: MIME type whitelist + Sharp metadata validation
- **Size Limits**: 10MB maximum enforced by both Multer and nginx
- **Path Safety**: Random filenames prevent traversal, validated absolute paths
- **Security Headers**: Helmet middleware adds production-ready headers
- **HTTPS**: Always use SSL in production (nginx + Let's Encrypt)

## Monitoring

### Service Management

```bash
# Check service status
sudo systemctl status image-server

# Start/stop/restart service
sudo systemctl start image-server
sudo systemctl stop image-server
sudo systemctl restart image-server
```

### Logs
```bash
# View real-time logs
sudo journalctl -u image-server -f

# View recent logs (last 100 lines)
sudo journalctl -u image-server -n 100

# View logs since boot
sudo journalctl -u image-server -b
```

### Disk Space
```bash
# Check upload directory size
du -sh /path/to/uploads

# Find large files
find /path/to/uploads -type f -size +5M
```

### Health Check Monitoring
Set up monitoring to ping `/health` endpoint regularly:
```bash
curl http://localhost:3000/health
```

## Troubleshooting

### API Key Invalid on Startup
```
ERROR: API_KEY must be set in .env file and be at least 32 characters long.
```
**Solution**: Generate a new key with the provided command and add to `.env`

### Port Already in Use
```
Error: listen EADDRINUSE: address already in use :::3000
```
**Solution**: Change `PORT` in `.env` or stop the conflicting service

### Images Not Accessible (Production)
**Issue**: Upload succeeds but URLs return 404
**Solution**: 
- Check nginx configuration: `/etc/nginx/sites-available/yourdomain.com`
- Ensure `alias` path in nginx matches your `UPLOAD_DIR`
- Verify nginx is running: `sudo systemctl status nginx`
- Test nginx config: `sudo nginx -t`

### Images Not Accessible (Development)
**Issue**: Getting 404 on image URLs in standalone mode
**Solution**: Make sure server.js has the static middleware enabled (should be by default)

### Disk Full Errors (507)
**Solution**: Clear old images or increase disk space
```bash
# Find and remove images older than 90 days
find /path/to/uploads -type f -mtime +90 -delete
```

## Testing

### Quick Test

If you used `./install.sh`, check `installation-info.txt` for your API key and test command.

### Manual Test

```bash
# Create a test image (if you don't have one)
curl -o test.jpg https://picsum.photos/800/600

# For production (with domain):
curl -X POST \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -F "image=@test.jpg" \
  https://images.yourdomain.com/upload

# For development (localhost):
curl -X POST \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -F "image=@test.jpg" \
  http://localhost:3000/upload

# The response will include the URL to access the optimized image
```

### Test Invalid Auth
```bash
curl -X POST \
  -H "Authorization: Bearer invalid_key" \
  -F "image=@test.jpg" \
  http://localhost:3000/upload

# Expected: 403 Forbidden
```

### Test Health Check
```bash
# Development:
curl http://localhost:3000/health

# Production:
curl https://images.yourdomain.com/health

# Expected: {"status":"ok",...}
```

## Files Generated by install.sh

After running `./install.sh`, these files are created:

- `.env` - Your configuration with API key
- `installation-info.txt` - Complete installation details (contains API key - keep secure!)
- `/etc/nginx/sites-available/yourdomain.com` - nginx configuration
- `/etc/nginx/sites-enabled/yourdomain.com` - Symlink to configuration
- `/etc/systemd/system/image-server.service` - systemd service file

## Project Structure

```
.
├── .env                    # Configuration (not in git)
├── .env.example            # Configuration template
├── .github/
│   └── copilot-instructions.md
├── .gitignore
├── install.sh              # Automated installation script
├── installation-info.txt   # Generated by install.sh (not in git)
├── node_modules/           # Dependencies
├── package.json
├── package-lock.json
├── README.md               # This file
├── server.js               # Main server file
└── uploads/                # Image storage (not in git)
```

## License

MIT
