# Template Files

This directory contains template files for setting up new Homebridge locations.

## Quick Start

1. Generate a location-specific homebridge YAML:
   ```bash
   LOCATION=us-ca envsubst < homebridge.yaml.template > homebridge-us-ca.yaml
   ```

2. Generate certificate request configuration:
   ```bash
   export LOCATION=us-ca \
          COUNTRY_CODE=US \
          STATE_OR_PROVINCE=California \
          CITY="Los Angeles" \
          ORGANIZATION_NAME="Your Organization" \
          ORGANIZATIONAL_UNIT="Your Unit" \
          DOMAIN_NAME="home.example.com" \
          EMAIL_ADDRESS="admin@example.com"
   
   envsubst < secrets/certificates/certificate-request.conf.template \
            > secrets/certificates/us-ca/certificate-request.conf
   ```

3. Generate certificates using makefile:
   ```bash
   make Generate-Secrets-Certificate LOCATION=us-ca
   ```

## Template Variables

### homebridge.yaml.template
- `${LOCATION}` - Location identifier (e.g., us-ca, us-ny)

### certificate-request.conf.template
- `${LOCATION}` - Location identifier
- `${COUNTRY_CODE}` - Two-letter country code
- `${STATE_OR_PROVINCE}` - Full state or province name
- `${CITY}` - City name
- `${ORGANIZATION_NAME}` - Organization name
- `${ORGANIZATIONAL_UNIT}` - Department or unit
- `${DOMAIN_NAME}` - Base domain for certificate CN
- `${EMAIL_ADDRESS}` - Contact email address

## Example

```bash
# Set all variables
export LOCATION=us-ca
export COUNTRY_CODE=US
export STATE_OR_PROVINCE=California
export CITY="Los Angeles"
export ORGANIZATION_NAME="My Home"
export ORGANIZATIONAL_UNIT="Network"
export DOMAIN_NAME="home.example.com"
export EMAIL_ADDRESS="admin@example.com"

# Generate homebridge YAML
envsubst < homebridge.yaml.template > homebridge-${LOCATION}.yaml

# Create certificate directory
mkdir --parents secrets/certificates/${LOCATION}

# Generate certificate config
envsubst < secrets/certificates/certificate-request.conf.template \
         > secrets/certificates/${LOCATION}/certificate-request.conf

# Generate certificates
make Generate-Secrets-Certificate LOCATION=${LOCATION}

# Create volumes directory
mkdir --parents volumes/${LOCATION}
```
