#!/bin/bash

# CDN Analyzer - Analyserar CDN-användning för streamingtjänster
# Kräver: traceroute, dig, curl, whois

set -euo pipefail

# Färger för output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funktioner
print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}           CDN ANALYZER SCRIPT${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo
}

print_section() {
    echo -e "${YELLOW}--- $1 ---${NC}"
}

check_dependencies() {
    local deps=("traceroute" "dig" "curl" "whois")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}Saknade verktyg: ${missing[*]}${NC}"
        echo "Installera med: brew install ${missing[*]} (macOS) eller apt install ${missing[*]} (Linux)"
        exit 1
    fi
}

get_domain_from_url() {
    echo "$1" | sed -E 's|^https?://||' | sed -E 's|/.*$||' | sed -E 's|:.*$||'
}

analyze_dns() {
    local domain="$1"
    print_section "DNS-analys för $domain"
    
    echo "A-records:"
    dig +short A "$domain" | while read -r ip; do
        if [ -n "$ip" ]; then
            echo "  $ip"
            # Försök identifiera CDN baserat på whois
            local org=$(whois "$ip" 2>/dev/null | grep -i "orgname\|org-name\|organization" | head -1 | cut -d: -f2 | xargs)
            if [ -n "$org" ]; then
                echo "    Organisation: $org"
            fi
        fi
    done
    echo
    
    echo "CNAME-records:"
    dig +short CNAME "$domain" | while read -r cname; do
        if [ -n "$cname" ]; then
            echo "  $cname"
            # Identifiera kända CDN:er baserat på CNAME
            case "$cname" in
                *cloudfront*) echo "    → Amazon CloudFront CDN" ;;
                *fastly*) echo "    → Fastly CDN" ;;
                *cloudflare*) echo "    → Cloudflare CDN" ;;
                *akamai*) echo "    → Akamai CDN" ;;
                *edgecast*) echo "    → Edgecast CDN" ;;
                *maxcdn*) echo "    → MaxCDN" ;;
                *keycdn*) echo "    → KeyCDN" ;;
                *bunnycdn*) echo "    → BunnyCDN" ;;
            esac
        fi
    done
    echo
}

perform_traceroute() {
    local target="$1"
    print_section "Traceroute till $target"
    
    echo "Spårar vägen till $target..."
    traceroute -m 20 "$target" 2>/dev/null | while read -r line; do
        if [[ "$line" =~ ^[[:space:]]*[0-9]+ ]]; then
            echo "$line"
            # Extrahera IP-adresser från traceroute-output
            local ips=$(echo "$line" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
            if [ -n "$ips" ]; then
                # Försök reverse DNS lookup
                local hostname=$(dig +short -x "$ips" 2>/dev/null | head -1)
                if [ -n "$hostname" ]; then
                    echo "    Hostname: $hostname"
                    # Identifiera CDN baserat på hostname
                    case "$hostname" in
                        *amazon*|*aws*) echo "    → Amazon/AWS infrastruktur" ;;
                        *google*|*goog*) echo "    → Google infrastruktur" ;;
                        *cloudflare*) echo "    → Cloudflare" ;;
                        *akamai*) echo "    → Akamai" ;;
                        *fastly*) echo "    → Fastly" ;;
                        *level3*) echo "    → Level3/CenturyLink" ;;
                        *telia*) echo "    → Telia" ;;
                    esac
                fi
            fi
        fi
    done
    echo
}

analyze_http_headers() {
    local url="$1"
    print_section "HTTP Headers-analys för $url"
    
    echo "Hämtar HTTP headers..."
    local headers=$(curl -s -I -L "$url" 2>/dev/null)
    
    # Analysera CDN-relaterade headers
    echo "$headers" | while IFS=: read -r key value; do
        key=$(echo "$key" | tr '[:upper:]' '[:lower:]' | xargs)
        value=$(echo "$value" | xargs)
        
        case "$key" in
            "server")
                echo "Server: $value"
                case "$value" in
                    *cloudflare*) echo "  → Cloudflare CDN detekterat" ;;
                    *nginx*) echo "  → Nginx (möjligen CDN)" ;;
                    *apache*) echo "  → Apache server" ;;
                esac
                ;;
            "x-served-by"|"x-cache"|"x-amz-cf-id"|"cf-ray")
                echo "$key: $value"
                case "$key" in
                    "x-amz-cf-id") echo "  → Amazon CloudFront detekterat" ;;
                    "cf-ray") echo "  → Cloudflare detekterat" ;;
                    "x-served-by") echo "  → Fastly eller Varnish cache" ;;
                esac
                ;;
            "x-edge-location"|"x-cache-status"|"x-cdn")
                echo "$key: $value"
                echo "  → CDN detekterat"
                ;;
        esac
    done
    echo
}

test_multiple_locations() {
    local domain="$1"
    print_section "Test från olika nätverkspositioner"
    
    echo "Tips: För komplett analys, kör detta script från olika nätverk/platser"
    echo "CDN:er använder anycast och geo-routing som kan ge olika resultat"
    echo
    
    # Visa aktuell offentlig IP för referens
    echo "Din nuvarande offentliga IP:"
    curl -s https://ipinfo.io/ip 2>/dev/null || echo "Kunde inte hämta offentlig IP"
    echo
}

main() {
    local url="$1"
    local domain
    
    print_header
    
    # Kontrollera beroenden
    check_dependencies
    
    # Extrahera domän från URL
    domain=$(get_domain_from_url "$url")
    echo -e "${GREEN}Analyserar: $domain${NC}"
    echo
    
    # Utför analyserna
    analyze_dns "$domain"
    perform_traceroute "$domain"
    analyze_http_headers "$url"
    test_multiple_locations "$domain"
    
    print_section "Sammanfattning"
    echo "Analys klar för $domain"
    echo "För djupare analys, överväg att använda:"
    echo "  - Wireshark för paketanalys"
    echo "  - mtr för kontinuerlig traceroute"
    echo "  - nmap för portscanning"
    echo "  - whatweb för webteknologi-identifiering"
    echo
}

# Kontrollera argument
if [ $# -eq 0 ]; then
    echo "Användning: $0 <URL eller domän>"
    echo "Exempel: $0 https://www.netflix.com"
    echo "         $0 https://www.svtplay.se"
    echo "         $0 youtube.com"
    exit 1
fi

main "$1"
