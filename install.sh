#!/bin/bash

set -e

echo "========================================"
echo "  Snapie Image Server Installation Script"
echo "========================================"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
   echo "⚠️  Please do not run this script as root/sudo"
   echo "   The script will ask for sudo when needed"
   exit 1
fi

# Get current directory
INSTALL_DIR=$(pwd)
echo "📁 Installation directory: $INSTALL_DIR"
echo ""

# Check if required commands exist
for cmd in node npm nginx systemctl; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ Error: $cmd is not installed"
        exit 1
    fi
done

echo "✅ All required commands found (node, npm, nginx, systemctl)"
echo ""

# ==========================================
# Step 1: Find available port
# ==========================================
echo "🔍 Finding available ports..."
echo ""

check_port() {
    if ! netstat -tuln 2>/dev/null | grep -q ":$1 "; then
        return 0
    else
        return 1
    fi
}

# Check common ports
AVAILABLE_PORTS=()
for port in 3000 3001 3002 3003 3004 3005 8080 8081 8082; do
    if check_port $port; then
        AVAILABLE_PORTS+=($port)
    fi
done

if [ ${#AVAILABLE_PORTS[@]} -eq 0 ]; then
    echo "⚠️  Common ports are busy. Please enter a custom port:"
    read -p "Port: " PORT
else
    echo "Available ports: ${AVAILABLE_PORTS[@]}"
    read -p "Choose a port [${AVAILABLE_PORTS[0]}]: " PORT
    PORT=${PORT:-${AVAILABLE_PORTS[0]}}
fi

echo "✅ Using port: $PORT"
echo ""

# ==========================================
# Step 2: Get domain information
# ==========================================
echo "🌐 Domain Configuration"
echo ""
read -p "Enter your domain (e.g., images.example.com): " DOMAIN

if [ -z "$DOMAIN" ]; then
    echo "❌ Domain is required"
    exit 1
fi

echo "✅ Domain: $DOMAIN"
echo ""

# ==========================================
# Step 3: Generate API Key
# ==========================================
echo "🔑 Generating secure API key..."
API_KEY=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
echo "✅ API Key generated: ${API_KEY:0:16}..."
echo ""

# ==========================================
# Step 4: Create .env file
# ==========================================
echo "📝 Creating .env file..."

cat > "$INSTALL_DIR/.env" << EOF
# Server Configuration
PORT=$PORT

# API Key for upload authentication
API_KEY=$API_KEY

# Storage Configuration
UPLOAD_DIR=$INSTALL_DIR/uploads

# Base URL for image access
BASE_URL=https://$DOMAIN
EOF

echo "✅ .env file created"
echo ""

# ==========================================
# Step 5: Install dependencies
# ==========================================
echo "📦 Installing Node.js dependencies..."
npm install --production
echo "✅ Dependencies installed"
echo ""

# ==========================================
# Step 6: Create uploads directory
# ==========================================
mkdir -p "$INSTALL_DIR/uploads"
echo "✅ Uploads directory created"
echo ""

# ==========================================
# Step 7: Create nginx configuration
# ==========================================
echo "🔧 Creating nginx configuration..."

NGINX_CONFIG="/tmp/image-server-${DOMAIN}.conf"

cat > "$NGINX_CONFIG" << EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    # Maximum upload size (must match or exceed Node.js limit)
    client_max_body_size 10M;
    
    # Upload endpoint - proxy to Node.js
    location /upload {
        proxy_pass http://localhost:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # Timeout for large uploads
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
    }
    
    # Health check endpoint
    location /health {
        proxy_pass http://localhost:$PORT;
        access_log off;
    }
    
    # Static image serving
    location /images/ {
        alias $INSTALL_DIR/uploads/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
}
EOF

echo "✅ nginx configuration created"
echo ""

# ==========================================
# Step 8: Install nginx configuration
# ==========================================
echo "📋 Installing nginx configuration..."
echo "   This requires sudo access..."

sudo cp "$NGINX_CONFIG" "/etc/nginx/sites-available/$DOMAIN"
sudo ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"

echo "✅ nginx configuration installed"
echo ""

# Test nginx configuration
echo "🧪 Testing nginx configuration..."
if sudo nginx -t; then
    echo "✅ nginx configuration is valid"
else
    echo "❌ nginx configuration test failed"
    exit 1
fi
echo ""

# ==========================================
# Step 9: Create systemd service
# ==========================================
echo "🔧 Creating systemd service..."

SERVICE_NAME="image-server"
SERVICE_FILE="/tmp/${SERVICE_NAME}.service"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Image Upload and Optimization Server
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$INSTALL_DIR
Environment="NODE_ENV=production"
ExecStart=$(which node) $INSTALL_DIR/server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "✅ systemd service file created"
echo ""

# ==========================================
# Step 10: Install systemd service
# ==========================================
echo "📋 Installing systemd service..."
echo "   This requires sudo access..."

sudo cp "$SERVICE_FILE" "/etc/systemd/system/${SERVICE_NAME}.service"
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}.service"

echo "✅ systemd service installed and enabled"
echo ""

# ==========================================
# Step 11: Start services
# ==========================================
echo "🚀 Starting services..."
echo ""

# Start image server
sudo systemctl start "${SERVICE_NAME}.service"
sleep 2

if sudo systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    echo "✅ Image server started successfully"
else
    echo "❌ Failed to start image server"
    echo "   Check logs with: sudo journalctl -u ${SERVICE_NAME} -n 50"
    exit 1
fi

# Reload nginx
sudo systemctl reload nginx
echo "✅ nginx reloaded"
echo ""

# ==========================================
# Step 12: SSL Certificate (optional)
# ==========================================
echo "🔒 SSL Certificate Setup"
echo ""
read -p "Do you want to install SSL certificate with certbot? (y/n) [y]: " INSTALL_SSL
INSTALL_SSL=${INSTALL_SSL:-y}

if [ "$INSTALL_SSL" = "y" ] || [ "$INSTALL_SSL" = "Y" ]; then
    if command -v certbot &> /dev/null; then
        echo "📜 Installing SSL certificate..."
        sudo certbot --nginx -d "$DOMAIN"
        echo "✅ SSL certificate installed"
    else
        echo "⚠️  certbot not found. Install it with:"
        echo "   sudo apt install certbot python3-certbot-nginx"
        echo "   Then run: sudo certbot --nginx -d $DOMAIN"
    fi
else
    echo "⚠️  Skipping SSL installation"
    echo "   To install later, run: sudo certbot --nginx -d $DOMAIN"
fi

echo ""
echo "========================================"
echo "  ✅ Installation Complete!"
echo "========================================"
echo ""
echo "📝 Configuration Summary:"
echo "   Domain:        $DOMAIN"
echo "   Port:          $PORT"
echo "   Install Dir:   $INSTALL_DIR"
echo "   Upload Dir:    $INSTALL_DIR/uploads"
echo "   API Key:       $API_KEY"
echo ""
echo "🔧 Useful Commands:"
echo "   Check status:  sudo systemctl status $SERVICE_NAME"
echo "   View logs:     sudo journalctl -u $SERVICE_NAME -f"
echo "   Restart:       sudo systemctl restart $SERVICE_NAME"
echo "   Stop:          sudo systemctl stop $SERVICE_NAME"
echo ""
echo "🧪 Test Upload:"
echo "   curl -X POST \\"
echo "     -H \"Authorization: Bearer $API_KEY\" \\"
echo "     -F \"image=@your-image.jpg\" \\"
echo "     https://$DOMAIN/upload"
echo ""
echo "📖 Full documentation: $INSTALL_DIR/README.md"
echo ""

# Save installation info
cat > "$INSTALL_DIR/installation-info.txt" << EOF
Image Server Installation Info
==============================
Date: $(date)
Domain: $DOMAIN
Port: $PORT
API Key: $API_KEY
Install Directory: $INSTALL_DIR
Upload Directory: $INSTALL_DIR/uploads
Service Name: $SERVICE_NAME
nginx Config: /etc/nginx/sites-available/$DOMAIN
systemd Service: /etc/systemd/system/${SERVICE_NAME}.service

Test Command:
curl -X POST \\
  -H "Authorization: Bearer $API_KEY" \\
  -F "image=@your-image.jpg" \\
  https://$DOMAIN/upload
EOF

echo "💾 Installation details saved to: $INSTALL_DIR/installation-info.txt"
echo ""
