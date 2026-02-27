# Image Server Project - Copilot Instructions

This is a Node.js image upload and optimization server built with Express, Sharp, and Multer.

## Project Overview
- Purpose: Fallback image server for production use
- Stack: Node.js, Express, Sharp (image processing), Multer (uploads)
- Features: API key authentication, WebP conversion, metadata stripping
- Architecture: Single-service upload/optimization with nginx static serving

## Key Design Decisions
- Single-file server (server.js) for simplicity
- Memory storage → Sharp processing → disk save (efficient)
- Always output WebP format (quality 80)
- Nginx serves static files for better performance
- Bearer token authentication for security

## Development Guidelines
- Keep implementation simple and reliable (this is a fallback service)
- Explicit error handling for production scenarios
- No unnecessary dependencies
- Environment-based configuration
- Validate all inputs and API keys on startup
