#!/bin/bash

# CDN Analyzer - Analyserar CDN-användning för streamingtjänster med grafisk representation
# Kräver: traceroute, dig, curl, whois, gnuplot (valfritt)
# Kompatibel med bash 3.x och 4.x

set -euo pipefail

# Färger för output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# ASCII-symboler för grafisk representation
GRAPH_CHARS=("█" "▉" "▊" "▋" "▌" "▍" "▎" "▏")
NODE_CHAR="●"
ARROW_CHAR="→"
PATH_CHAR="│"

# Global arrays för data
declare -a hop_ips=()
declare -a hop_hostnames=()
declare -a hop_latencies=()
declare -a hop_providers=()

print_banner() {
    echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║            CDN ANALYZER v2.0               ║${NC}"
    echo -e "${BLUE}║         Grafisk nätverksanalys             ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
    echo
}

print_ascii_box() {
    local title="$1"
    local width=50
    local title_len=${#title}
    local padding=$(( (width - title_len - 2) / 2 ))

    echo -e "${YELLOW}┌$(printf '─%.0s' $(seq 1 $width))┐${NC}"
    printf "${YELLOW}│%*s%s%*s│${NC}\n" $padding "" "$title" $padding ""
    echo -e "${YELLOW}└$(printf '─%.0s' $(seq 1 $width))┘${NC}"
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

    # Kontrollera om gnuplot finns för avancerade grafer
    if command -v gnuplot &> /dev/null; then
        echo -e "${GREEN}✓ Gnuplot hittad - avancerade grafer tillgängliga${NC}"
        GNUPLOT_AVAILABLE=true
    else
        echo -e "${YELLOW}! Gnuplot saknas - endast ASCII-grafer tillgängliga${NC}"
        echo "  Installera med: brew install gnuplot (macOS)"
        GNUPLOT_AVAILABLE=false
    fi
    echo
}

get_domain_from_url() {
    echo "$1" | sed -E 's|^https?://||' | sed -E 's|/.*$||' | sed -E 's|:.*$||'
}

identify_provider() {
    local hostname="$1"
    local ip="$2"

    case "$hostname" in
        *amazon*|*aws*|*cloudfront*) echo "Amazon/AWS" ;;
        *google*|*goog*|*youtube*) echo "Google" ;;
        *cloudflare*) echo "Cloudflare" ;;
        *akamai*) echo "Akamai" ;;
        *fastly*) echo "Fastly" ;;
        *level3*) echo "Level3" ;;
        *telia*) echo "Telia" ;;
        *netflix*) echo "Netflix" ;;
        *edgecast*) echo "Edgecast" ;;
        *)
            # Försök med whois om hostname inte matchar
            local org=$(whois "$ip" 2>/dev/null | grep -i "orgname\|org-name\|organization" | head -1 | cut -d: -f2 | xargs 2>/dev/null)
            if [ -n "$org" ]; then
                echo "$org" | cut -c1-15
            else
                echo "Okänd"
            fi
            ;;
    esac
}

draw_latency_bar_safe() {
    local latency="$1"
    local max_width=20
    local max_latency=200  # ms

    if [[ "$latency" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        # Använd awk istället för bc för bättre kompatibilitet
        local width=$(awk "BEGIN {printf \"%.0f\", $latency * $max_width / $max_latency}")
        if [ "$width" -gt "$max_width" ]; then
            width=$max_width
        fi
        if [ "$width" -lt 1 ]; then
            width=1
        fi

        # Färgkodning baserat på latens
        local color=""
        if (( $(awk "BEGIN {print ($latency < 20)}") )); then
            color=$GREEN
        elif (( $(awk "BEGIN {print ($latency < 50)}") )); then
            color=$YELLOW
        else
            color=$RED
        fi

        local bars=""
        for ((i=0; i<width; i++)); do
            bars="${bars}█"
        done
        echo "${color}${bars}${NC} ${latency}ms"
    else
        echo "N/A"
    fi
}

analyze_dns_visual() {
    local domain="$1"
    print_ascii_box "DNS-ANALYS: $domain"

    echo -e "${CYAN}A-Records:${NC}"
    local ips=($(dig +short A "$domain"))
    local ip_count=${#ips[@]}

    for i in "${!ips[@]}"; do
        local ip="${ips[$i]}"
        local org=$(whois "$ip" 2>/dev/null | grep -i "orgname\|org-name\|organization" | head -1 | cut -d: -f2 | xargs 2>/dev/null || echo "Okänd")
        local percentage=$(awk "BEGIN {printf \"%.1f\", 100 / $ip_count}")

        echo "  ${NODE_CHAR} $ip ${ARROW_CHAR} ${org:0:20} ($percentage%)"
    done
    echo

    echo -e "${CYAN}CNAME-Records:${NC}"
    local cnames=($(dig +short CNAME "$domain"))
    if [ ${#cnames[@]} -eq 0 ]; then
        echo "  Inga CNAME-records hittade"
    else
        for cname in "${cnames[@]}"; do
            local cdn_type="Okänd CDN"
            case "$cname" in
                *cloudfront*) cdn_type="Amazon CloudFront" ;;
                *fastly*) cdn_type="Fastly CDN" ;;
                *cloudflare*) cdn_type="Cloudflare CDN" ;;
                *akamai*) cdn_type="Akamai CDN" ;;
                *edgecast*) cdn_type="Edgecast CDN" ;;
            esac
            echo "  ${NODE_CHAR} $cname ${ARROW_CHAR} $cdn_type"
        done
    fi
    echo
}

perform_traceroute_visual() {
    local target="$1"
    print_ascii_box "NÄTVERKSVÄG TILL $target"

    echo -e "${CYAN}Traceroute med latensvisualisering:${NC}"
    echo

    # Rensa tidigare data
    hop_ips=()
    hop_hostnames=()
    hop_latencies=()
    hop_providers=()

    local hop_num=0
    local traceroute_output=$(traceroute -m 20 "$target" 2>&1)

    if [ $? -ne 0 ]; then
        echo -e "${RED}Traceroute misslyckades. Försöker alternativ metod...${NC}"
        # Försök med ping som backup
        local ping_result=$(ping -c 1 "$target" 2>/dev/null)
        if echo "$ping_result" | grep -q "PING"; then
            local ip=$(echo "$ping_result" | grep "PING" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
            if [ -n "$ip" ]; then
                hop_ips=("$ip")
                hop_hostnames=("$target")
                hop_latencies=("direct")
                hop_providers=("Direct connection")
                echo "1. ${NODE_CHAR} $target ${PATH_CHAR} Direct ${PATH_CHAR} Direkt anslutning"
            fi
        else
            echo -e "${RED}Kunde inte nå $target${NC}"
        fi
        echo
        return
    fi

    echo "$traceroute_output" | while read -r line; do
        if [[ "$line" =~ ^[[:space:]]*([0-9]+)[[:space:]]+(.+) ]]; then
            local hop="${BASH_REMATCH[1]}"
            local rest="${BASH_REMATCH[2]}"

            # Extrahera IP och latens
            local ip=$(echo "$rest" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
            local latency=$(echo "$rest" | grep -oE '[0-9]+\.[0-9]+ ms' | head -1 | cut -d' ' -f1)

            if [ -n "$ip" ]; then
                local hostname=$(dig +short -x "$ip" 2>/dev/null | head -1 | sed 's/\.$//')
                if [ -z "$hostname" ]; then
                    hostname="$ip"
                fi

                local provider=$(identify_provider "$hostname" "$ip")

                # Visa hopp med grafisk representation
                echo "$hop. ${NODE_CHAR} ${hostname:0:30} ${PATH_CHAR} $provider ${PATH_CHAR} $(draw_latency_bar_safe "$latency")"

                # Spara data för senare analys (utanför subshell)
                echo "$ip|$hostname|$latency|$provider" >> "/tmp/traceroute_data_$"
            fi
        fi
    done

    # Läs tillbaka data från temporär fil
    if [ -f "/tmp/traceroute_data_$" ]; then
        while IFS='|' read -r ip hostname latency provider; do
            hop_ips+=("$ip")
            hop_hostnames+=("$hostname")
            hop_latencies+=("$latency")
            hop_providers+=("$provider")
        done < "/tmp/traceroute_data_$"
        rm -f "/tmp/traceroute_data_$"
    fi

    if [ ${#hop_ips[@]} -eq 0 ]; then
        echo -e "${YELLOW}Ingen traceroute-data erhölls. Möjliga orsaker:${NC}"
        echo "  - Brandvägg blockerar ICMP/UDP"
        echo "  - Nätverket tillåter inte traceroute"
        echo "  - Destinationen svarar inte på traceroute"
        echo
    fi
    echo
}

analyze_http_headers_visual() {
    local url="$1"
    print_ascii_box "HTTP HEADERS ANALYS"

    echo -e "${CYAN}CDN-detektering via HTTP headers:${NC}"

    local headers=$(curl -s -I -L "$url" 2>/dev/null)
    local cdn_detected=false

    echo "$headers" | while IFS=: read -r key value; do
        key=$(echo "$key" | tr '[:upper:]' '[:lower:]' | xargs)
        value=$(echo "$value" | xargs)

        case "$key" in
            "server")
                printf "  Server: %s\n" "$value"
                case "$value" in
                    *cloudflare*) echo "    ${GREEN}✓ Cloudflare CDN detekterat${NC}"; cdn_detected=true ;;
                    *nginx*) echo "    ${YELLOW}? Möjligen CDN (Nginx)${NC}" ;;
                esac
                ;;
            "x-served-by"|"x-cache"|"x-amz-cf-id"|"cf-ray"|"x-edge-location")
                printf "  %s: %s\n" "$key" "$value"
                case "$key" in
                    "x-amz-cf-id") echo "    ${GREEN}✓ Amazon CloudFront detekterat${NC}"; cdn_detected=true ;;
                    "cf-ray") echo "    ${GREEN}✓ Cloudflare detekterat${NC}"; cdn_detected=true ;;
                    "x-served-by") echo "    ${GREEN}✓ Fastly/Varnish detekterat${NC}"; cdn_detected=true ;;
                    "x-edge-location") echo "    ${GREEN}✓ CDN edge location detekterat${NC}"; cdn_detected=true ;;
                esac
                ;;
        esac
    done

    if [ "$cdn_detected" = false ]; then
        echo -e "  ${YELLOW}! Ingen tydlig CDN detekterad via headers${NC}"
    fi
    echo
}

create_latency_graph() {
    local output_file="$1"

    if [ "$GNUPLOT_AVAILABLE" = false ]; then
        return
    fi

    # Skapa datafil för gnuplot
    local data_file="/tmp/latency_data.txt"
    for i in "${!hop_latencies[@]}"; do
        if [[ "${hop_latencies[$i]}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "$((i+1)) ${hop_latencies[$i]} \"${hop_providers[$i]}\"" >> "$data_file"
        fi
    done

    # Skapa gnuplot-script
    cat > "/tmp/latency_plot.gp" << EOF
set terminal png size 800,600
set output '$output_file'
set title 'Latens per hopp i nätverket'
set xlabel 'Hopp nummer'
set ylabel 'Latens (ms)'
set grid
set style data linespoints
plot '$data_file' using 1:2 with linespoints title 'Latens', \\
     '' using 1:2:3 with labels offset char 1,1 notitle
EOF

    gnuplot "/tmp/latency_plot.gp" 2>/dev/null

    # Städa upp
    rm -f "$data_file" "/tmp/latency_plot.gp"
}

create_provider_chart() {
    local output_file="$1"

    if [ "$GNUPLOT_AVAILABLE" = false ]; then
        return
    fi

    # Kontrollera om vi har data
    if [ ${#hop_providers[@]} -eq 0 ]; then
        return
    fi

    # Räkna leverantörer med en enklare metod
    local data_file="/tmp/provider_data.txt"
    printf '%s\n' "${hop_providers[@]}" | sort | uniq -c | sort -nr > "/tmp/provider_count.txt"

    # Skapa dataformatet för gnuplot
    local i=0
    while read -r count provider; do
        echo "$i \"$provider\" $count" >> "$data_file"
        ((i++))
    done < "/tmp/provider_count.txt"

    # Skapa stapeldiagram
    cat > "/tmp/provider_plot.gp" << EOF
set terminal png size 800,400
set output '$output_file'
set title 'Nätverksleverantörer i vägen'
set ylabel 'Antal hopp'
set style data histogram
set style fill solid border -1
set boxwidth 0.9
set xtics rotate by -45
plot '$data_file' using 3:xtic(2) title 'Hopp per leverantör'
EOF

    gnuplot "/tmp/provider_plot.gp" 2>/dev/null

    # Städa upp
    rm -f "$data_file" "/tmp/provider_plot.gp" "/tmp/provider_count.txt"
}

generate_html_report() {
    local domain="$1"
    local output_file="cdn_report_$(date +%Y%m%d_%H%M%S).html"

    # Sätt UTF-8 locale för korrekt teckenkodning
    export LC_ALL=en_US.UTF-8 2>/dev/null || export LC_ALL=C.UTF-8 2>/dev/null || true

    cat > "$output_file" << EOF
<!DOCTYPE html>
<html lang="sv">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CDN Analys - $domain</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 2px solid #007acc; padding-bottom: 10px; }
        h2 { color: #007acc; margin-top: 30px; }
        .metric { background: #f8f9fa; padding: 15px; margin: 10px 0; border-left: 4px solid #007acc; }
        .graph { text-align: center; margin: 20px 0; }
        .hop-list { font-family: monospace; background: #f8f9fa; padding: 15px; border-radius: 4px; }
        .timestamp { color: #666; font-size: 0.9em; }
        .warning { background: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 10px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>CDN Analys för $domain</h1>
        <p class="timestamp">Genererad: $(date)</p>

        <h2>Översikt</h2>
        <div class="metric">
            <strong>Analyserad domän:</strong> $domain<br>
            <strong>Antal hopp:</strong> ${#hop_ips[@]}<br>
EOF

    if [ ${#hop_ips[@]} -eq 0 ]; then
        cat >> "$output_file" << EOF
            <strong>Status:</strong> <span style="color: orange;">Ingen traceroute-data tillgänglig</span>
        </div>

        <div class="warning">
            <strong>⚠ Information:</strong> Traceroute kunde inte utföras. Detta kan bero på brandväggar,
            nätverksbegränsningar eller att destinationen inte svarar på traceroute-förfrågningar.
            DNS- och HTTP-analys genomfördes istället.
        </div>
EOF
    else
        local unique_providers=($(printf '%s\n' "${hop_providers[@]}" | sort -u))
        cat >> "$output_file" << EOF
            <strong>Unika leverantörer:</strong> ${#unique_providers[@]}
        </div>

        <h2>Nätverksväg</h2>
        <div class="hop-list">
EOF

        for i in "${!hop_ips[@]}"; do
            echo "Hopp $((i+1)): ${hop_hostnames[$i]} (${hop_providers[$i]}) - ${hop_latencies[$i]}ms<br>" >> "$output_file"
        done

        echo "</div>" >> "$output_file"
    fi

    cat >> "$output_file" << EOF

        <h2>Grafer</h2>
        <div class="graph">
EOF

    if [ "$GNUPLOT_AVAILABLE" = true ] && [ ${#hop_ips[@]} -gt 0 ]; then
        local latency_graph="latency_graph_$(date +%Y%m%d_%H%M%S).png"
        local provider_chart="provider_chart_$(date +%Y%m%d_%H%M%S).png"

        create_latency_graph "$latency_graph"
        create_provider_chart "$provider_chart"

        echo "<h3>Latens per hopp</h3>" >> "$output_file"
        echo "<img src=\"$latency_graph\" alt=\"Latensdiagram\"><br><br>" >> "$output_file"
        echo "<h3>Leverantörsfördelning</h3>" >> "$output_file"
        echo "<img src=\"$provider_chart\" alt=\"Leverantörsdiagram\">" >> "$output_file"
    else
        if [ ${#hop_ips[@]} -eq 0 ]; then
            echo "<p><em>Inga grafer kan skapas utan traceroute-data</em></p>" >> "$output_file"
        else
            echo "<p><em>Installera gnuplot för att se grafer</em></p>" >> "$output_file"
        fi
    fi

    cat >> "$output_file" << EOF
        </div>
    </div>
</body>
</html>
EOF

    echo -e "${GREEN}✓ HTML-rapport skapad: $output_file${NC}"
    echo -e "  Öppna med: open '$output_file' (macOS) eller xdg-open '$output_file' (Linux)"

    # Kontrollera filkodning
    if command -v file &> /dev/null; then
        local encoding=$(file -b --mime-encoding "$output_file" 2>/dev/null || echo "unknown")
        if [ "$encoding" != "utf-8" ]; then
            echo -e "${YELLOW}  ⚠ Varning: Filkodning är $encoding, UTF-8 rekommenderas${NC}"
        fi
    fi
}

print_summary() {
    local domain="$1"
    print_ascii_box "SAMMANFATTNING"

    echo -e "${CYAN}Nätverksanalys för $domain:${NC}"
    echo -e "  ${NODE_CHAR} Totalt antal hopp: ${#hop_ips[@]}"

    # Kontrollera om vi har data
    if [ ${#hop_ips[@]} -eq 0 ]; then
        echo -e "  ${YELLOW}⚠ Ingen traceroute-data tillgänglig${NC}"
        echo -e "  ${YELLOW}⚠ Analysera DNS och HTTP headers istället${NC}"
        echo
        return
    fi

    # Räkna unika leverantörer
    local unique_providers=($(printf '%s\n' "${hop_providers[@]}" | sort -u))
    echo -e "  ${NODE_CHAR} Unika leverantörer: ${#unique_providers[@]}"

    # Beräkna genomsnittlig latens med awk istället för bc
    local total_latency=0
    local valid_latencies=0
    for latency in "${hop_latencies[@]}"; do
        if [[ "$latency" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            total_latency=$(awk "BEGIN {print $total_latency + $latency}")
            ((valid_latencies++))
        fi
    done

    if [ "$valid_latencies" -gt 0 ]; then
        local avg_latency=$(awk "BEGIN {printf \"%.1f\", $total_latency / $valid_latencies}")
        echo -e "  ${NODE_CHAR} Genomsnittlig latens: ${avg_latency}ms"
    fi

    echo
    echo -e "${YELLOW}Detekterade leverantörer:${NC}"
    for provider in "${unique_providers[@]}"; do
        local count=$(printf '%s\n' "${hop_providers[@]}" | grep -c "^$provider$" || echo "0")
        echo "  ${ARROW_CHAR} $provider ($count hopp)"
    done
    echo
}

main() {
    local url="$1"
    local domain

    print_banner

    # Kontrollera beroenden
    check_dependencies

    # Extrahera domän från URL
    domain=$(get_domain_from_url "$url")
    echo -e "${GREEN}🎯 Analyserar: $domain${NC}"
    echo

    # Utför analyserna med grafisk representation
    analyze_dns_visual "$domain"
    perform_traceroute_visual "$domain"
    analyze_http_headers_visual "$url"

    # Skapa sammanfattning
    print_summary "$domain"

    # Generera HTML-rapport
    echo -e "${CYAN}Skapar detaljerad rapport...${NC}"
    generate_html_report "$domain"
    echo

    echo -e "${GREEN}✅ Analys klar!${NC}"
    echo -e "${YELLOW}Tips:${NC}"
    echo "  • Installera gnuplot för avancerade grafer: brew install gnuplot"
    echo "  • Kör från olika nätverk för att se CDN-skillnader"
    echo "  • Använd Wireshark för djupare paketanalys"
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
