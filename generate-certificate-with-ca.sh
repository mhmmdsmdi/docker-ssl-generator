#!/bin/bash

#==============================================================================
# SSL/TLS Certificate Generator for Docker Applications
# 
# This script generates certificates for:
# - ASP.NET Core applications in Docker
# - React applications with Nginx in Docker
#==============================================================================

# Set up directories
mkdir -p certs
mkdir -p examples

#------------------------------------------------------------------------------
# HELPER FUNCTIONS
#------------------------------------------------------------------------------

# Generate CA certificate and key if they don't exist (NEW FUNCTION)
generate_ca() {
    mkdir -p certs/ca
    if [ ! -f "certs/ca/ca.key" ] || [ ! -f "certs/ca/ca.crt" ]; then
        echo "Generating Certificate Authority..."
        openssl genrsa -out certs/ca/ca.key 4096
        openssl req -new -x509 -days 3650 -key certs/ca/ca.key -out certs/ca/ca.crt \
            -subj "/C=$CERT_COUNTRY/ST=$CERT_STATE/L=$CERT_LOCALITY/O=$CERT_ORG/CN=Local Certificate Authority"
        echo "✅ CA files created in certs/ca/"
    fi
}

# Generate a secure alphanumeric password (20 characters)
generate_password() {
  LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20
}

# Display Docker environment configuration help for ASP.NET Core
show_aspnet_docker_config() {
  local cert_file=$1
  local port=$2
  local password=$3
  local tls_version=$4

  echo ""
  echo "======== ASP.NET CORE DOCKER CONFIGURATION ========"
  echo "Add these environment variables to your Docker Compose file:"
  echo "environment:"
  echo "  - ASPNETCORE_URLS=https://+:$port"
  echo "  - ASPNETCORE_Kestrel__Certificates__Default__Password=$password"
  echo "  - ASPNETCORE_Kestrel__Certificates__Default__Path=/app/certs/$cert_file"
  
  # Add TLS version configuration if specified
  if [ ! -z "$tls_version" ]; then
    echo "  - ASPNETCORE_Kestrel__Endpoints__Https__Protocols=$tls_version"
  fi
  
  echo ""
  echo "And don't forget to add this volume mapping:"
  echo "volumes:"
  echo "  - ./certs:/app/certs"
  echo "=================================================="
}

# Display Nginx configuration for React apps
show_nginx_config() {
  local domain=$1
  local cert_path=$2
  local key_path=$3
  local tls_version=$4

  # Map TLS version selection to Nginx config
  local ssl_protocols=""
  case "$tls_version" in
    "1")
      ssl_protocols="ssl_protocols TLSv1.2 TLSv1.3;"
      ;;
    "2")
      ssl_protocols="ssl_protocols TLSv1.3;"
      ;;
    "3")
      ssl_protocols="ssl_protocols TLSv1.2;"
      ;;
    "4")
      ssl_protocols="ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;"
      ;;
    *)
      ssl_protocols="ssl_protocols TLSv1.2 TLSv1.3;"
      ;;
  esac

  echo ""
  echo "======== NGINX CONFIGURATION FOR REACT APP ========"
  echo "1. Add these volumes to your Docker Compose file:"
  echo "volumes:"
  echo "  - ./certs:/etc/nginx/certs"
  echo "  - ./nginx.conf:/etc/nginx/conf.d/default.conf"
  echo ""
  echo "2. Create a nginx.conf file with the following content:"
  echo ""
  echo "server {"
  echo "    listen 80;"
  echo "    listen 443 ssl;"
  echo "    server_name $domain;"
  echo ""
  echo "    ssl_certificate /etc/nginx/certs/$cert_path;"
  echo "    ssl_certificate_key /etc/nginx/certs/$key_path;"
  echo ""
  echo "    # SSL configuration"
  echo "    $ssl_protocols"
  echo "    ssl_prefer_server_ciphers on;"
  echo "    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;"
  echo "    ssl_session_timeout 1d;"
  echo "    ssl_session_cache shared:SSL:10m;"
  echo "    ssl_session_tickets off;"
  echo ""
  echo "    # For React SPA routing"
  echo "    location / {"
  echo "        root /usr/share/nginx/html;"
  echo "        index index.html index.htm;"
  echo "        try_files \$uri \$uri/ /index.html;"
  echo "    }"
  echo "}"
  echo ""
  echo "3. In your Dockerfile, include:"
  echo "FROM nginx:alpine"
  echo "COPY build/ /usr/share/nginx/html/"
  echo "=================================================="
  echo ""
  echo "Example configuration files have been created in the 'examples' directory."
}

# Generate the private key based on algorithm choice
generate_key() {
  local key_path=$1
  local algorithm=$2

  if [[ "$algorithm" == ec:* ]]; then
    openssl ecparam -genkey -name ${algorithm#ec:} -out "$key_path"
  else
    openssl genrsa -out "$key_path" ${algorithm#rsa:}
  fi
}

# Create OpenSSL config for domain certificates
create_domain_config() {
  local config_file=$1
  local domain=$2
  local cert_country=$3
  local cert_state=$4
  local cert_locality=$5
  local cert_org=$6
  local cert_options=$7
  local additional_domains=$8

  cat > "$config_file" << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = req_distinguished_name
EOF

  # Add extensions if requested
  if [ "$cert_options" = "1" ] || [ "$cert_options" = "3" ]; then
    cat >> "$config_file" << EOF
req_extensions = v3_req

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $domain
EOF
    
    # Add additional domains if provided
    if [ ! -z "$additional_domains" ]; then
      IFS=',' read -ra DOMAINS <<< "$additional_domains"
      i=2
      for domain in "${DOMAINS[@]}"; do
        echo "DNS.$i = $domain" >> "$config_file"
        i=$((i+1))
      done
    fi
  fi

  # Add extended key usage if requested
  if [ "$cert_options" = "2" ] || [ "$cert_options" = "3" ]; then
    if ! grep -q "v3_req" "$config_file"; then
      cat >> "$config_file" << EOF
req_extensions = v3_req

[v3_req]
EOF
    fi
    
    cat >> "$config_file" << EOF
extendedKeyUsage = serverAuth, clientAuth
keyUsage = digitalSignature, keyEncipherment
EOF
  fi

  cat >> "$config_file" << EOF
[req_distinguished_name]
C = $cert_country
ST = $cert_state
L = $cert_locality
O = $cert_org
CN = $domain
EOF
}

# Create OpenSSL config for IP certificates
create_ip_config() {
  local config_file=$1
  local ip_address=$2
  local cert_country=$3
  local cert_state=$4
  local cert_locality=$5
  local cert_org=$6
  local cert_options=$7
  local additional_ips=$8

  cat > "$config_file" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = $cert_country
ST = $cert_state
L = $cert_locality
O = $cert_org
CN = $ip_address

[v3_req]
EOF

  # Add extended key usage if requested
  if [ "$cert_options" = "2" ] || [ "$cert_options" = "3" ]; then
    cat >> "$config_file" << EOF
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
EOF
  else
    cat >> "$config_file" << EOF
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
EOF
  fi

  cat >> "$config_file" << EOF
subjectAltName = @alt_names

[alt_names]
IP.1 = $ip_address
EOF

  # Add additional IPs if provided
  if [ "$cert_options" = "1" ] || [ "$cert_options" = "3" ]; then
    if [ ! -z "$additional_ips" ]; then
      IFS=',' read -ra IPS <<< "$additional_ips"
      i=2
      for ip in "${IPS[@]}"; do
        echo "IP.$i = $ip" >> "$config_file"
        i=$((i+1))
      done
    fi
  fi
}

#------------------------------------------------------------------------------
# USER INPUT COLLECTION
#------------------------------------------------------------------------------

# Application type selection
echo "===== APPLICATION TYPE ====="
echo "1) ASP.NET Core application"
echo "2) React app with Nginx"
echo "3) General purpose SSL/TLS certificate"
read -p "Enter your choice (1-3): " APP_TYPE

# Certificate type selection
echo ""
echo "===== CERTIFICATE TYPE ====="
echo "1) Domain certificate (e.g., myapplication.example.com)"
echo "2) IP address certificate (e.g., 10.20.30.40:8443)"
read -p "Enter your choice (1 or 2): " CERT_TYPE

# NEW CA SELECTION PROMPT
echo ""
read -p "Sign certificate with a CA? [y/N] " USE_CA
USE_CA=${USE_CA:-n}

# Password option selection for ASP.NET (not needed for Nginx)
if [ "$APP_TYPE" = "1" ]; then
  echo ""
  echo "===== PASSWORD OPTIONS ====="
  echo "1) Generate a random password (alphanumeric only)"
  echo "2) Enter your own password"
  read -p "Enter your choice (1 or 2): " PASS_CHOICE

  if [ "$PASS_CHOICE" = "1" ]; then
    CERT_PASSWORD=$(generate_password)
    echo "Generated password: $CERT_PASSWORD"
    echo "IMPORTANT: Save this password for your ASP.NET Core application!"
  else
    read -sp "Enter a password for the certificate: " CERT_PASSWORD
    echo ""
  fi
fi

# Encryption algorithm selection
echo ""
echo "===== ENCRYPTION OPTIONS ====="
echo "1) RSA 2048-bit (default, more compatible)"
echo "2) RSA 4096-bit (stronger but larger)"
echo "3) ECC (Elliptic Curve, modern and compact)"
read -p "Enter your choice (1-3): " ENCRYPTION_CHOICE

case "$ENCRYPTION_CHOICE" in
  "2")
    KEY_ALGORITHM="rsa:4096"
    echo "Using RSA 4096-bit encryption"
    ;;
  "3")
    KEY_ALGORITHM="ec:secp384r1"
    echo "Using Elliptic Curve encryption (secp384r1)"
    ;;
  *)
    KEY_ALGORITHM="rsa:2048"
    echo "Using RSA 2048-bit encryption (default)"
    ;;
esac

# TLS version selection
echo ""
echo "===== TLS VERSION OPTIONS ====="
echo "1) TLS 1.2 and 1.3 (recommended default)"
echo "2) TLS 1.3 only (highest security, less compatible)"
echo "3) TLS 1.2 only (better compatibility)"
echo "4) All TLS versions (highest compatibility, less secure)"
read -p "Enter your choice (1-4): " TLS_VERSION_CHOICE

# Map TLS version to ASP.NET configuration
case "$TLS_VERSION_CHOICE" in
  "1")
    ASPNET_TLS="Tls12,Tls13"
    echo "Using TLS 1.2 and 1.3"
    ;;
  "2")
    ASPNET_TLS="Tls13"
    echo "Using TLS 1.3 only"
    ;;
  "3")
    ASPNET_TLS="Tls12"
    echo "Using TLS 1.2 only"
    ;;
  "4")
    ASPNET_TLS="Tls,Tls11,Tls12,Tls13"
    echo "Using all TLS versions (1.0, 1.1, 1.2, 1.3)"
    ;;
  *)
    ASPNET_TLS="Tls12,Tls13"
    echo "Using TLS 1.2 and 1.3 (default)"
    ;;
esac

# Certificate validity period
echo ""
read -p "Enter certificate validity in days (default: 365): " CERT_DAYS
CERT_DAYS=${CERT_DAYS:-365}

# Additional certificate options
echo ""
echo "===== ADDITIONAL OPTIONS ====="
echo "1) Include subject alternative names (SANs)"
echo "2) Add extended key usage extensions"
echo "3) Include both options"
echo "4) Basic certificate only (default)"
read -p "Enter your choice (1-4): " CERT_OPTIONS

#------------------------------------------------------------------------------
# CERTIFICATE SUBJECT DETAILS
#------------------------------------------------------------------------------

echo ""
echo "===== CERTIFICATE SUBJECT DETAILS ====="
echo "Enter the following details (or press Enter for defaults):"
read -p "Country (C) [Example: US, DE, GB, IR] (default: US): " CERT_COUNTRY
CERT_COUNTRY=${CERT_COUNTRY:-US}

read -p "State/Province (ST) [Example: California, Berlin, Tehran] (default: State): " CERT_STATE
CERT_STATE=${CERT_STATE:-State}

read -p "Locality/City (L) [Example: San Francisco, Berlin, Tehran] (default: City): " CERT_LOCALITY
CERT_LOCALITY=${CERT_LOCALITY:-City}

read -p "Organization (O) [Example: MyCompany Inc, CloudApps] (default: CloudApps): " CERT_ORG
CERT_ORG=${CERT_ORG:-CloudApps}

echo "Using subject details: C=$CERT_COUNTRY, ST=$CERT_STATE, L=$CERT_LOCALITY, O=$CERT_ORG"


#------------------------------------------------------------------------------
# CERTIFICATE GENERATION
#------------------------------------------------------------------------------

if [ "$CERT_TYPE" = "1" ]; then
  #-----------------------------------
  # DOMAIN CERTIFICATE
  #-----------------------------------
  read -p "Enter domain name (default: myapplication.example.com): " DOMAIN
  DOMAIN=${DOMAIN:-myapplication.example.com}
  
  # Ask for additional domains if SANs are requested
  if [ "$CERT_OPTIONS" = "1" ] || [ "$CERT_OPTIONS" = "3" ]; then
    read -p "Enter additional domain names (comma-separated, e.g. www.example.com,api.example.com): " ADDITIONAL_DOMAINS
  fi
  
  echo ""
  echo "Generating certificate for domain: $DOMAIN"
  
  # Create OpenSSL config file for domain
  CONFIG_FILE="domain_$DOMAIN.conf"
  create_domain_config "$CONFIG_FILE" "$DOMAIN" "$CERT_COUNTRY" "$CERT_STATE" "$CERT_LOCALITY" "$CERT_ORG" "$CERT_OPTIONS" "$ADDITIONAL_DOMAINS"
  
  # Generate private key
  generate_key "$DOMAIN.key" "$KEY_ALGORITHM"
  
  # Create CSR (Certificate Signing Request)
  openssl req -new -key "$DOMAIN.key" -out "$DOMAIN.csr" -config "$CONFIG_FILE"
  
  # Generate certificate
  if [[ $USE_CA =~ [Yy] ]]; then
    generate_ca
    if [ "$CERT_OPTIONS" = "1" ] || [ "$CERT_OPTIONS" = "2" ] || [ "$CERT_OPTIONS" = "3" ]; then
		  openssl x509 -req -days $CERT_DAYS -in "$DOMAIN.csr" -CA certs/ca/ca.crt -CAkey certs/ca/ca.key -CAcreateserial -out "$DOMAIN.crt" -extensions v3_req -extfile "$CONFIG_FILE"
	  else
		  openssl x509 -req -days $CERT_DAYS -in "$DOMAIN.csr" -CA certs/ca/ca.crt -CAkey certs/ca/ca.key -CAcreateserial -out "$DOMAIN.crt"
	  fi	
  else
    if [ "$CERT_OPTIONS" = "1" ] || [ "$CERT_OPTIONS" = "2" ] || [ "$CERT_OPTIONS" = "3" ]; then
		  openssl x509 -req -days $CERT_DAYS -in "$DOMAIN.csr" -signkey "$DOMAIN.key" -out "$DOMAIN.crt" -extensions v3_req -extfile "$CONFIG_FILE"
	  else
		  openssl x509 -req -days $CERT_DAYS -in "$DOMAIN.csr" -signkey "$DOMAIN.key" -out "$DOMAIN.crt"
	  fi
  fi
  
  # Move the key and certificate files to the certs directory
  mv "$DOMAIN.key" "certs/"
  mv "$DOMAIN.crt" "certs/"
  
  # Process based on application type
  if [ "$APP_TYPE" = "1" ]; then
    # Create PFX file for ASP.NET Core
    openssl pkcs12 -export -out "certs/$DOMAIN.pfx" -inkey "certs/$DOMAIN.key" -in "certs/$DOMAIN.crt" -password pass:$CERT_PASSWORD

    echo "✅ Domain certificate created at: certs/$DOMAIN.pfx"
    
    # Display ASP.NET Core Docker configuration help
    show_aspnet_docker_config "$DOMAIN.pfx" "443" "$CERT_PASSWORD" "$ASPNET_TLS"
    
    # Create example docker-compose.yml file for ASP.NET Core
    cat > examples/aspnet-docker-compose.yml << EOF
version: '3'

services:
  aspnet-app:
    image: your-aspnet-image:latest
    ports:
      - "443:443"
    environment:
      - ASPNETCORE_URLS=https://+:443
      - ASPNETCORE_Kestrel__Certificates__Default__Password=$CERT_PASSWORD
      - ASPNETCORE_Kestrel__Certificates__Default__Path=/app/certs/$DOMAIN.pfx
      - ASPNETCORE_Kestrel__Endpoints__Https__Protocols=$ASPNET_TLS
    volumes:
      - ./certs:/app/certs
EOF
    echo "✅ Example Docker Compose file created at: examples/aspnet-docker-compose.yml"
    
  elif [ "$APP_TYPE" = "2" ] || [ "$APP_TYPE" = "3" ]; then
    echo "✅ Certificate files created:"
    echo "   - certs/$DOMAIN.crt (certificate file)"
    echo "   - certs/$DOMAIN.key (private key file)"
    
    if [ "$APP_TYPE" = "2" ]; then
      # Display Nginx configuration for React apps
      show_nginx_config "$DOMAIN" "$DOMAIN.crt" "$DOMAIN.key" "$TLS_VERSION_CHOICE"
      
      # Create example nginx.conf file
      # Map TLS version selection to Nginx config
      local ssl_protocols=""
      case "$TLS_VERSION_CHOICE" in
        "1")
          ssl_protocols="ssl_protocols TLSv1.2 TLSv1.3;"
          ;;
        "2")
          ssl_protocols="ssl_protocols TLSv1.3;"
          ;;
        "3")
          ssl_protocols="ssl_protocols TLSv1.2;"
          ;;
        "4")
          ssl_protocols="ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;"
          ;;
        *)
          ssl_protocols="ssl_protocols TLSv1.2 TLSv1.3;"
          ;;
      esac
      
      cat > examples/nginx.conf << EOF
server {
    listen 80;
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/nginx/certs/$DOMAIN.crt;
    ssl_certificate_key /etc/nginx/certs/$DOMAIN.key;

    # SSL configuration
    $ssl_protocols
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    # For React SPA routing
    location / {
        root /usr/share/nginx/html;
        index index.html index.htm;
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
      echo "✅ Example Nginx configuration created at: examples/nginx.conf"
      
      # Create example docker-compose.yml file
      cat > examples/docker-compose.yml << EOF
version: '3'

services:
  react-app:
    build: .
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./certs:/etc/nginx/certs
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
EOF
      echo "✅ Example Docker Compose file created at: examples/docker-compose.yml"
      
      # Create example Dockerfile
      cat > examples/Dockerfile << EOF
# Build stage
FROM node:16-alpine as build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# Production stage
FROM nginx:alpine
COPY --from=build /app/build /usr/share/nginx/html
EXPOSE 80 443
CMD ["nginx", "-g", "daemon off;"]
EOF
      echo "✅ Example Dockerfile created at: examples/Dockerfile"
    fi
  fi
  
elif [ "$CERT_TYPE" = "2" ]; then
  #-----------------------------------
  # IP ADDRESS CERTIFICATE
  #-----------------------------------
  read -p "Enter IP address (default: 10.20.30.40): " IP_ADDRESS
  IP_ADDRESS=${IP_ADDRESS:-10.20.30.40}
  
  read -p "Enter port (default: 8443): " PORT
  PORT=${PORT:-8443}
  
  # Ask for additional IPs if SANs are requested
  if [ "$CERT_OPTIONS" = "1" ] || [ "$CERT_OPTIONS" = "3" ]; then
    read -p "Enter additional IP addresses (comma-separated, e.g. 10.0.0.1,172.16.0.1): " ADDITIONAL_IPS
  fi
  
  echo ""
  echo "Generating certificate for IP: $IP_ADDRESS and port: $PORT"
  
  # Create config file for IP
  CONFIG_FILE="ip_$IP_ADDRESS.conf"
  create_ip_config "$CONFIG_FILE" "$IP_ADDRESS" "$CERT_COUNTRY" "$CERT_STATE" "$CERT_LOCALITY" "$CERT_ORG" "$CERT_OPTIONS" "$ADDITIONAL_IPS"
  
  # Generate private key
  generate_key "ipaddress.key" "$KEY_ALGORITHM"
  
  # Create CSR with the config
  openssl req -new -key "ipaddress.key" -out "ipaddress.csr" -config "$CONFIG_FILE"
  
  # MODIFIED CERTIFICATE GENERATION WITH CA SUPPORT
  if [[ $USE_CA =~ [Yy] ]]; then
    generate_ca
    openssl x509 -req -days $CERT_DAYS -in "ipaddress.csr" -CA certs/ca/ca.crt -CAkey certs/ca/ca.key -CAcreateserial -out "ipaddress.crt" -extensions v3_req -extfile "$CONFIG_FILE"
  else
    openssl x509 -req -days $CERT_DAYS -in "ipaddress.csr" -signkey "ipaddress.key" -out "ipaddress.crt" -extensions v3_req -extfile "$CONFIG_FILE"
  fi
  
  # Move the key and certificate files to the certs directory
  mv "ipaddress.key" "certs/"
  mv "ipaddress.crt" "certs/"
  
  # Process based on application type
  if [ "$APP_TYPE" = "1" ]; then
    # Create PFX file for ASP.NET Core
    openssl pkcs12 -export -out "certs/ipaddress.pfx" -inkey "certs/ipaddress.key" -in "certs/ipaddress.crt" -password pass:$CERT_PASSWORD

    echo "✅ IP certificate created at: certs/ipaddress.pfx"
    
    # Display ASP.NET Core Docker configuration help
    show_aspnet_docker_config "ipaddress.pfx" "$PORT" "$CERT_PASSWORD" "$ASPNET_TLS"
    
    # Create example docker-compose.yml file for ASP.NET Core with IP
    cat > examples/aspnet-ip-docker-compose.yml << EOF
version: '3'

services:
  aspnet-app:
    image: your-aspnet-image:latest
    ports:
      - "$PORT:$PORT"
    environment:
      - ASPNETCORE_URLS=https://+:$PORT
      - ASPNETCORE_Kestrel__Certificates__Default__Password=$CERT_PASSWORD
      - ASPNETCORE_Kestrel__Certificates__Default__Path=/app/certs/ipaddress.pfx
      - ASPNETCORE_Kestrel__Endpoints__Https__Protocols=$ASPNET_TLS
    volumes:
      - ./certs:/app/certs
EOF
    echo "✅ Example Docker Compose file created at: examples/aspnet-ip-docker-compose.yml"
    
  elif [ "$APP_TYPE" = "2" ] || [ "$APP_TYPE" = "3" ]; then
    echo "✅ Certificate files created:"
    echo "   - certs/ipaddress.crt (certificate file)"
    echo "   - certs/ipaddress.key (private key file)"
    
    if [ "$APP_TYPE" = "2" ]; then
      # Display Nginx configuration for React apps
      show_nginx_config "$IP_ADDRESS" "ipaddress.crt" "ipaddress.key" "$TLS_VERSION_CHOICE"
      
      # Create example nginx.conf file for IP
      # Map TLS version selection to Nginx config
      local ssl_protocols=""
      case "$TLS_VERSION_CHOICE" in
        "1")
          ssl_protocols="ssl_protocols TLSv1.2 TLSv1.3;"
          ;;
        "2")
          ssl_protocols="ssl_protocols TLSv1.3;"
          ;;
        "3")
          ssl_protocols="ssl_protocols TLSv1.2;"
          ;;
        "4")
          ssl_protocols="ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;"
          ;;
        *)
          ssl_protocols="ssl_protocols TLSv1.2 TLSv1.3;"
          ;;
      esac
      
      cat > examples/nginx-ip.conf << EOF
server {
    listen 80;
    listen $PORT ssl;
    server_name $IP_ADDRESS;

    ssl_certificate /etc/nginx/certs/ipaddress.crt;
    ssl_certificate_key /etc/nginx/certs/ipaddress.key;

    # SSL configuration
    $ssl_protocols
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    # For React SPA routing
    location / {
        root /usr/share/nginx/html;
        index index.html index.htm;
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
      echo "✅ Example Nginx configuration created at: examples/nginx-ip.conf"
      
      # Create example docker-compose.yml file for IP
      cat > examples/docker-compose-ip.yml << EOF
version: '3'

services:
  react-app:
    build: .
    ports:
      - "80:80"
      - "$PORT:$PORT"
    volumes:
      - ./certs:/etc/nginx/certs
      - ./nginx-ip.conf:/etc/nginx/conf.d/default.conf
EOF
      echo "✅ Example Docker Compose file created at: examples/docker-compose-ip.yml"
      
      # Create example Dockerfile for IP
      cat > examples/Dockerfile-ip << EOF
# Build stage
FROM node:16-alpine as build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# Production stage
FROM nginx:alpine
COPY --from=build /app/build /usr/share/nginx/html
EXPOSE 80 $PORT
CMD ["nginx", "-g", "daemon off;"]
EOF
      echo "✅ Example Dockerfile created at: examples/Dockerfile-ip"
    fi
  fi
  
else
  echo "❌ Invalid choice. Please run the script again and select 1 or 2."
  exit 1
fi

# Cleanup temporary files
rm -f *.csr
rm -f *.conf
rm -f certs/ca/*.srl 

#------------------------------------------------------------------------------
# FINALIZATION
#------------------------------------------------------------------------------

# Save the password to a file for reference if using ASP.NET
if [ "$APP_TYPE" = "1" ]; then
  echo "$CERT_PASSWORD" > certs/cert-password.txt
  chmod 600 certs/cert-password.txt
  echo ""
  echo "🔑 Password saved to certs/cert-password.txt for your reference."
fi

# NEW CA INSTRUCTIONS
if [[ $USE_CA =~ [Yy] ]]; then
    echo ""
    echo "🔑 CA IMPORTANT: To trust this certificate, install these files:"
    echo "   - certs/ca/ca.crt (CA certificate)"
    echo "   - certs/ca/ca.key (CA private key - keep secure!)"
    echo "On Linux systems, you can trust the CA with:"
    echo "sudo cp certs/ca/ca.crt /usr/local/share/ca-certificates/"
    echo "sudo update-ca-certificates"
fi

echo ""
echo "✅ Certificate generation completed successfully!"
echo ""
echo "📂 Certificate files are located in the 'certs' directory."
echo "📂 Example configuration files are located in the 'examples' directory."