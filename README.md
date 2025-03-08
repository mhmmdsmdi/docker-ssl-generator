# SSL/TLS Certificate Generator

A bash script for generating self-signed SSL/TLS certificates for Docker-based applications, focusing on ASP.NET Core and React/Nginx setups.

## 🚀 Features

- Generate certificates for:
  - ASP.NET Core applications in Docker
  - React applications with Nginx in Docker
  - General purpose SSL/TLS certificates
- Support for domain-based or IP-based certificates
- Multiple encryption options (RSA 2048/4096, ECC)
- Configurable TLS versions
- Subject Alternative Names (SANs) support
- Extended key usage options
- Example configuration files for Docker, ASP.NET, and Nginx

## 📋 Prerequisites

- OpenSSL installed on your system
- Bash shell environment

## 📥 Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/username/docker-ssl-generator.git
   cd docker-ssl-generator
   ```

2. Make the script executable:
   ```bash
   chmod +x generate-certificate.sh
   ```

## 🔧 Usage

Run the script and follow the interactive prompts:

```bash
./generate-certificate.sh
```

### Options

The script will guide you through several options:

1. **Application Type**
   - ASP.NET Core application
   - React app with Nginx
   - General purpose SSL/TLS certificate

2. **Certificate Type**
   - Domain certificate (e.g., myapplication.example.com)
   - IP address certificate (e.g., 10.20.30.40:8443)

3. **Password Options** (ASP.NET Core only)
   - Generate a random password
   - Enter your own password

4. **Encryption Options**
   - RSA 2048-bit (default, more compatible)
   - RSA 4096-bit (stronger but larger)
   - ECC (Elliptic Curve, modern and compact)

5. **TLS Version Options**
   - TLS 1.2 and 1.3 (recommended default)
   - TLS 1.3 only (highest security, less compatible)
   - TLS 1.2 only (better compatibility)
   - All TLS versions (highest compatibility, less secure)

6. **Certificate Validity**
   - Enter number of days (default: 365)

7. **Additional Options**
   - Include subject alternative names (SANs)
   - Add extended key usage extensions
   - Include both options
   - Basic certificate only (default)

8. **Certificate Subject Details**
   - Country (C) [Example: US, DE, GB, IR]
   - State/Province (ST) [Example: California, Berlin, Tehran]
   - Locality/City (L) [Example: San Francisco, Berlin, Tehran]
   - Organization (O) [Example: MyCompany Inc, CloudApps]

## 📂 Output

The script creates two directories:

- `certs/`: Contains the generated certificate files (.crt, .key, .pfx)
- `examples/`: Contains sample configuration files for:
  - Docker Compose files
  - Nginx configuration
  - Dockerfile examples

## 🔐 ASP.NET Core Example

For ASP.NET Core applications, the script generates a .pfx file and provides the necessary environment variables for your Docker Compose file:

```yaml
version: '3'

services:
  aspnet-app:
    image: your-aspnet-image:latest
    ports:
      - "443:443"
    environment:
      - ASPNETCORE_URLS=https://+:443
      - ASPNETCORE_Kestrel__Certificates__Default__Password=YourPassword
      - ASPNETCORE_Kestrel__Certificates__Default__Path=/app/certs/yoursite.pfx
      - ASPNETCORE_Kestrel__Endpoints__Https__Protocols=Tls12,Tls13
    volumes:
      - ./certs:/app/certs
```

## 🌐 Nginx/React Example

For React applications with Nginx, the script generates certificate files and provides a sample Nginx configuration:

```nginx
server {
    listen 80;
    listen 443 ssl;
    server_name yourdomain.com;

    ssl_certificate /etc/nginx/certs/yourdomain.com.crt;
    ssl_certificate_key /etc/nginx/certs/yourdomain.com.key;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    # For React SPA routing
    location / {
        root /usr/share/nginx/html;
        index index.html index.htm;
        try_files $uri $uri/ /index.html;
    }
}
```

## ⚠️ Important Notes

- These are self-signed certificates intended for development and testing
- For production environments, use certificates from a trusted Certificate Authority
- The generated password for ASP.NET Core certificates is saved in `certs/cert-password.txt`

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.
