# CDN Analyzer v2.0

Ett omfattande bashscript för analys av Content Delivery Networks (CDN) och nätverksinfrastruktur för streamingtjänster och webbplatser.

## Funktioner

### 🎯 Nätverksanalys
- **Traceroute-visualisering** med färgkodade latensgrafer
- **DNS-analys** med A-records, CNAME-records och CDN-detektering
- **HTTP Headers-analys** för CDN-identifiering
- **Leverantörsidentifiering** baserat på hostname och whois-data

### 📊 Grafisk representation
- **ASCII-grafik** i terminalen med färgkodning (grön/gul/röd för latens)
- **HTML-rapporter** med responsiv design och CSS-styling
- **PNG-grafer** för latens och leverantörsfördelning (kräver gnuplot)
- **Realtidsvisualisering** av nätverksvägar

### 🛡️ Robust felhantering
- Graceful degradation när traceroute blockeras
- Backup-metoder med ping
- Kompatibilitet med både bash 3.x och 4.x
- Hantering av nätverksbegränsningar och brandväggar

## Installation

### Krav (obligatoriska)
```bash
# macOS
brew install traceroute bind whois curl

# Linux (Ubuntu/Debian)
sudo apt update
sudo apt install traceroute dnsutils whois curl

# Linux (CentOS/RHEL)
sudo yum install traceroute bind-utils whois curl
```

### Valfria beroenden
```bash
# För avancerade PNG-grafer
# macOS
brew install gnuplot

# Linux
sudo apt install gnuplot  # Ubuntu/Debian
sudo yum install gnuplot  # CentOS/RHEL
```

### Scriptet
```bash
# Ladda ner scriptet
curl -O https://raw.githubusercontent.com/[ditt-användarnamn]/cdn-analyzer/main/cdn_analyzer.sh

# Gör det körbart
chmod +x cdn_analyzer.sh
```

## Användning

### Grundläggande användning
```bash
# Analysera en webbplats
./cdn_analyzer.sh https://www.netflix.com

# Analysera utan protokoll
./cdn_analyzer.sh youtube.com

# Analysera svenska streamingtjänster
./cdn_analyzer.sh https://www.svtplay.se
./cdn_analyzer.sh https://www.tv4play.se
```

### Output-format

#### Terminal (ASCII-grafik)
```
╔════════════════════════════════════════════╗
║            CDN ANALYZER v2.0               ║
║         Grafisk nätverksanalys             ║
╚════════════════════════════════════════════╝

┌──────────────────────────────────────────────────┐
│              DNS-ANALYS: netflix.com            │
└──────────────────────────────────────────────────┘

A-Records:
  ● 54.230.162.85   → Amazon Technologies Inc (25.0%)
  ● 54.230.162.159  → Amazon Technologies Inc (25.0%)

1. ● router.local                     │ Lokalt          │ ████████ 8.2ms
2. ● telia-gw.example.com            │ Telia           │ ██████████ 15.4ms
3. ● amazon-edge.cloudfront.net      │ Amazon/AWS      │ ████████████ 24.1ms
```

#### HTML-rapport
- Responsiv webbdesign med CSS-styling
- Inbäddade PNG-grafer (om gnuplot finns)
- Detaljerad sammanfattning och metadata
- Mobilanpassad layout

#### PNG-grafer (med gnuplot)
- **Latensdiagram**: Linjegraf som visar latens per hopp
- **Leverantörsdiagram**: Stapeldiagram över nätverksleverantörer

## Exempel på användningsområden

### För cybersäkerhetsanalys
```bash
# Analysera potentiella säkerhetshot genom infrastruktur
./cdn_analyzer.sh suspicious-domain.com

# Dokumentera nätverksvägar för incident response
./cdn_analyzer.sh company-website.com > incident_analysis.txt
```

### För prestationsoptimering
```bash
# Jämför CDN-prestanda
./cdn_analyzer.sh https://www.competitor1.com
./cdn_analyzer.sh https://www.competitor2.com

# Analysera leverantörskedjan
for site in netflix.com hulu.com disney.com; do
    ./cdn_analyzer.sh "$site"
done
```

### För utbildning och demonstration
```bash
# Visa skillnader mellan globala CDN:er
./cdn_analyzer.sh https://www.cloudflare.com
./cdn_analyzer.sh https://aws.amazon.com
./cdn_analyzer.sh https://azure.microsoft.com
```

## Output-exempel

### Identifierade CDN-leverantörer
- **Amazon CloudFront**: Via X-Amz-Cf-Id headers och amazonaws domäner
- **Cloudflare**: Via CF-Ray headers och cloudflare CNAME-records
- **Fastly**: Via X-Served-By headers
- **Akamai**: Via akamai domännamn i traceroute
- **Google**: Via google/goog domäner
- **Edgecast/Verizon**: Via edgecast infrastruktur

### Teknisk information som extraheras
- **Latens per hopp** med färgkodning
- **Geografisk routing** baserat på hostname-mönster
- **Redundans och lastbalansering** via multipla A-records
- **Edge-lokationer** från CDN-specifika headers

## Tekniska detaljer

### Kompatibilitet
- **Bash**: 3.2+ (macOS standard) till 5.x (moderna Linux)
- **OS**: macOS 10.12+, Linux (alla större distributioner)
- **Arkitektur**: x86_64, ARM64 (Apple Silicon)

### Säkerhetsöverväganden
- Använder endast standard nätverksverktyg
- Ingen data skickas till externa tjänster
- All analys sker lokalt
- Respekterar rate limits och använder caching

### Felhantering
```bash
# Om traceroute blockeras
⚠ Traceroute misslyckades. Försöker alternativ metod...
# Scriptet fortsätter med ping och DNS/HTTP-analys

# Om gnuplot saknas
! Gnuplot saknas - endast ASCII-grafer tillgängliga
# Funktionalitet degraderas gracefully
```

## Felsökning

### Vanliga problem

#### "command not found: traceroute"
```bash
# macOS
brew install traceroute

# Linux
sudo apt install traceroute
```

#### "Ingen traceroute-data erhölls"
Detta är normalt för många moderna webbplatser som blockerar ICMP/UDP.
Scriptet kommer automatiskt använda alternativa metoder:
- DNS-analys för CDN-detektering
- HTTP headers för edge-identifiering
- Ping för grundläggande anslutningstest

#### "printf: invalid number"
Uppdatera till senaste versionen - äldre versioner hade problem med decimal-formatering.

#### UTF-8 teckenkodning i HTML
```bash
# Sätt korrekt locale före körning
export LC_ALL=en_US.UTF-8
./cdn_analyzer.sh example.com
```

### Debug-läge
```bash
# För detaljerad felsökning
bash -x ./cdn_analyzer.sh example.com > debug.log 2>&1
```

## Bidra till projektet

### Rapportera buggar
Skapa en issue med:
- OS och bash-version (`bash --version`)
- Kommando som kördes
- Förväntad vs faktisk output
- Relevanta felmeddelanden

### Föreslå förbättringar
- Stöd för fler CDN-leverantörer
- Ytterligare visualiseringsformat
- Integration med andra nätverksverktyg
- Prestationsförbättringar

### Utveckling
```bash
# Klona repot
git clone https://github.com/[ditt-användarnamn]/cdn-analyzer.git
cd cdn-analyzer

# Gör ändringar
nano cdn_analyzer.sh

# Testa på olika domäner
./cdn_analyzer.sh test-domain.com

# Skapa pull request
```

## Licens

MIT License - se LICENSE-filen för detaljer.

## Erkännanden

Utvecklat för cybersäkerhetsanalys och nätverksövervakning.
Testat på svenska och internationella streamingtjänster.

---

**Tips**: För bästa resultat, kör scriptet från olika nätverksplatser för att se hur CDN:er använder geo-routing och anycast.