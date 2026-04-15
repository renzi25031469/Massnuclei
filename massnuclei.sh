#!/bin/bash
# =============================================================================
# massnuclei.sh – Masscan + Nuclei automated scanner
# Uso: massnuclei.sh [opções] <arquivo_hosts>
# Author: Renzi
# =============================================================================

# ---------- Cores ----------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ---------- Banner ----------
banner() {
cat << "EOF"
 /$$      /$$                              /$$   /$$                     /$$           /$$
| $$$    /$$$                             | $$$ | $$                    | $$          |__/
| $$$$  /$$$$  /$$$$$$   /$$$$$$$ /$$$$$$$| $$$$| $$ /$$   /$$  /$$$$$$$| $$  /$$$$$$  /$$
| $$ $$/$$ $$ |____  $$ /$$_____//$$_____/| $$ $$ $$| $$  | $$ /$$_____/| $$ /$$__  $$| $$
| $$  $$$| $$  /$$$$$$$|  $$$$$$|  $$$$$$ | $$  $$$$| $$  | $$ | $$     | $$| $$$$$$$$| $$
| $$\  $ | $$ /$$__  $$ \____  $$\____  $$| $$\  $$$| $$  | $$ | $$     | $$| $$_____/| $$
| $$ \/  | $$|  $$$$$$$ /$$$$$$$//$$$$$$$/| $$ \  $$|  $$$$$$/  \$$$$$$$| $$ \$$$$$$$| $$
|__/     |__/ \_______/|_______/|_______/ |__/  \__/ \______/   \_______/|__/  \_____/|__/

                          Public and Private Programs
EOF
}

# ---------- Ajuda ----------
usage() {
  banner
  echo ""
  echo -e "${BOLD}Uso:${NC} massnuclei.sh [opções] <arquivo_hosts>"
  echo ""
  echo -e "${BOLD}Opções:${NC}"
  echo "  -b, --background       Executa em background (nohup)"
  echo "  -o, --output <dir>     Diretório de saída (padrão: ./output_<timestamp>)"
  echo "  -r, --rate <n>         Taxa do masscan (padrão: 10000)"
  echo "  -s, --severity <list>  Severidades do nuclei (padrão: critical,high,medium,low,unknown)"
  echo "  -c, --concurrency <n>  Concorrência do nuclei (padrão: 50)"
  echo "  -p, --ports <range>    Portas para varredura (padrão: 1-65535)"
  echo "  --no-txt               Não salva resultado bruto em TXT"
  echo "  -h, --help             Exibe esta ajuda"
  echo ""
  echo -e "${BOLD}Exemplos:${NC}"
  echo "  massnuclei.sh targets.txt"
  echo "  massnuclei.sh -b -o /tmp/scan targets.txt"
  echo "  massnuclei.sh --rate 5000 --severity critical,high targets.txt"
  exit 0
}

# ---------- Defaults ----------
BACKGROUND=false
OUTPUT_DIR=""
RATE=10000
SEVERITY="critical,high,medium,low,unknown"
CONCURRENCY=50
PORTS="1-65535"
SAVE_TXT=true
ARQUIVO_HOSTS=""

# ---------- Parse de argumentos ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--background)   BACKGROUND=true; shift ;;
    -o|--output)       OUTPUT_DIR="$2"; shift 2 ;;
    -r|--rate)         RATE="$2"; shift 2 ;;
    -s|--severity)     SEVERITY="$2"; shift 2 ;;
    -c|--concurrency)  CONCURRENCY="$2"; shift 2 ;;
    -p|--ports)        PORTS="$2"; shift 2 ;;
    --no-txt)          SAVE_TXT=false; shift ;;
    -h|--help)         usage ;;
    -*)                echo -e "${RED}Opção desconhecida: $1${NC}"; usage ;;
    *)                 ARQUIVO_HOSTS="$1"; shift ;;
  esac
done

# ---------- Validações ----------
if [ -z "$ARQUIVO_HOSTS" ]; then
  usage
fi

if [ ! -f "$ARQUIVO_HOSTS" ]; then
  echo -e "${RED}Erro:${NC} Arquivo '$ARQUIVO_HOSTS' não encontrado."
  exit 1
fi

for tool in masscan nuclei; do
  if ! command -v "$tool" &>/dev/null; then
    echo -e "${RED}Erro:${NC} '$tool' não está instalado ou não está no PATH."
    exit 1
  fi
done

# ---------- Correção Causa 1: libpcap ----------
check_fix_libpcap() {
  local test_out
  test_out=$(masscan --version 2>&1)
  if echo "$test_out" | grep -qi "failed to load libpcap"; then
    echo -e "${YELLOW}[!]${NC} libpcap não carregada. Tentando instalar..."
    if command -v apt-get &>/dev/null; then
      apt-get install -y libpcap-dev libpcap0.8 > /dev/null 2>&1 && \
        echo -e "${GREEN}[+]${NC} libpcap instalada com sucesso." || \
        { echo -e "${RED}[-]${NC} Falha ao instalar libpcap. Instale manualmente: apt-get install libpcap-dev"; exit 1; }
    elif command -v yum &>/dev/null; then
      yum install -y libpcap libpcap-devel > /dev/null 2>&1 && \
        echo -e "${GREEN}[+]${NC} libpcap instalada com sucesso." || \
        { echo -e "${RED}[-]${NC} Falha ao instalar libpcap. Instale manualmente: yum install libpcap-devel"; exit 1; }
    else
      echo -e "${RED}[-]${NC} Gerenciador de pacotes não suportado. Instale libpcap manualmente."
      exit 1
    fi
  fi

  local pcap_so
  pcap_so=$(ldconfig -p 2>/dev/null | grep 'libpcap\.so\b' | awk '{print $NF}' | head -1)
  if [ -z "$pcap_so" ]; then
    local pcap_versioned
    pcap_versioned=$(find /usr/lib /lib -name 'libpcap.so.*' 2>/dev/null | head -1)
    if [ -n "$pcap_versioned" ]; then
      local link_dir
      link_dir=$(dirname "$pcap_versioned")
      ln -sf "$pcap_versioned" "$link_dir/libpcap.so" 2>/dev/null && ldconfig 2>/dev/null
      echo -e "${GREEN}[+]${NC} Symlink libpcap criado: $link_dir/libpcap.so -> $pcap_versioned"
    fi
  fi
}

# ---------- Correção Causa 2: Gateway MAC para Masscan ----------
resolve_masscan_router_args() {
  MASSCAN_IFACE=$(awk 'NR>2 && $1 !~ /^lo/ {gsub(/:/, "", $1); print $1; exit}' /proc/net/dev 2>/dev/null)
  if [ -z "$MASSCAN_IFACE" ]; then
    echo -e "${YELLOW}[!]${NC} Interface de rede não detectada. Masscan usará detecção automática."
    MASSCAN_ROUTER_ARGS=""
    return
  fi

  local gw_hex gw_ip
  gw_hex=$(awk 'NR>1 && $2=="00000000" {print $3; exit}' /proc/net/route 2>/dev/null)
  if [ -n "$gw_hex" ]; then
    gw_ip=$(python3 -c "
h='$gw_hex'
b=bytes.fromhex(h)
print('.'.join(str(x) for x in reversed(b)))
" 2>/dev/null)
  fi

  if [ -z "$gw_ip" ] || [ "$gw_ip" = "0.0.0.0" ]; then
    echo -e "${YELLOW}[!]${NC} Gateway não detectado. Masscan usará broadcast MAC."
    MASSCAN_ROUTER_ARGS="--router-mac FF-FF-FF-FF-FF-FF"
    return
  fi

  ping -c 1 -W 1 "$gw_ip" > /dev/null 2>&1 || true
  sleep 0.5

  local gw_mac
  gw_mac=$(awk -v gw="$gw_ip" '$1==gw && $3!="0x0" {print $4; exit}' /proc/net/arp 2>/dev/null)

  if [ -n "$gw_mac" ] && [ "$gw_mac" != "00:00:00:00:00:00" ]; then
    local masscan_mac
    masscan_mac=$(echo "$gw_mac" | tr ':' '-' | tr 'a-f' 'A-F')
    echo -e "${GREEN}[+]${NC} Gateway: $gw_ip | MAC: $masscan_mac | Interface: $MASSCAN_IFACE"
    MASSCAN_ROUTER_ARGS="--router-mac $masscan_mac --interface $MASSCAN_IFACE"
  else
    if command -v arping &>/dev/null; then
      gw_mac=$(arping -c 1 -I "$MASSCAN_IFACE" "$gw_ip" 2>/dev/null \
               | grep -oP '(?<=\[)[0-9a-f:]+(?=\])' | head -1)
    fi

    if [ -n "$gw_mac" ] && [ "$gw_mac" != "00:00:00:00:00:00" ]; then
      local masscan_mac
      masscan_mac=$(echo "$gw_mac" | tr ':' '-' | tr 'a-f' 'A-F')
      echo -e "${GREEN}[+]${NC} Gateway: $gw_ip | MAC (arping): $masscan_mac | Interface: $MASSCAN_IFACE"
      MASSCAN_ROUTER_ARGS="--router-mac $masscan_mac --interface $MASSCAN_IFACE"
    else
      echo -e "${YELLOW}[!]${NC} MAC do gateway não resolvido (ARP timeout). Usando broadcast MAC como fallback."
      echo -e "${YELLOW}    ${NC} Gateway IP: $gw_ip | Interface: $MASSCAN_IFACE"
      echo -e "${YELLOW}    ${NC} Para forçar MAC correto: --router-mac <MAC> no masscan.conf"
      MASSCAN_ROUTER_ARGS="--router-mac FF-FF-FF-FF-FF-FF --interface $MASSCAN_IFACE"
    fi
  fi
}

# ---------- Diretório de saída ----------
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
[ -z "$OUTPUT_DIR" ] && OUTPUT_DIR="./output_${TIMESTAMP}"
mkdir -p "$OUTPUT_DIR"

MASSCAN_LOG="$OUTPUT_DIR/masscan.log"
NUCLEI_INPUT="$OUTPUT_DIR/nuclei_input.txt"
NUCLEI_TXT="$OUTPUT_DIR/nuclei_resultados.txt"
NUCLEI_JSON="$OUTPUT_DIR/nuclei_resultados.json"
SCAN_LOG="$OUTPUT_DIR/scan.log"

# ---------- Contagem de IPs únicos no arquivo de entrada ----------
# Remove linhas em branco, comentários e duplicatas antes de contar
TOTAL_INPUT_HOSTS=$(grep -v '^\s*$' "$ARQUIVO_HOSTS" | grep -v '^\s*#' | sort -u | wc -l | tr -d ' ')

# ---------- Modo background ----------
if $BACKGROUND; then
  SELF=$(realpath "$0")                          # caminho absoluto do próprio script
  ABS_HOSTS=$(realpath "$ARQUIVO_HOSTS")         # caminho absoluto do arquivo de hosts
  ABS_OUTPUT=$(realpath "$OUTPUT_DIR")           # caminho absoluto do diretório de saída

  # Reconstrói os argumentos a partir das variáveis já parseadas.
  # NÃO usa $@ pois ele está vazio depois do parse — todos os args foram consumidos.
  NEW_ARGS=(
    --output    "$ABS_OUTPUT"
    --rate      "$RATE"
    --severity  "$SEVERITY"
    --concurrency "$CONCURRENCY"
    --ports     "$PORTS"
  )
  $SAVE_TXT || NEW_ARGS+=(--no-txt)
  NEW_ARGS+=("$ABS_HOSTS")                       # arquivo de hosts sempre por último

  mkdir -p "$ABS_OUTPUT"
  echo -e "${CYAN}[*]${NC} Iniciando em background. PID salvo em: $ABS_OUTPUT/scan.pid"
  nohup bash "$SELF" "${NEW_ARGS[@]}" > "$ABS_OUTPUT/nohup.log" 2>&1 &
  echo $! > "$ABS_OUTPUT/scan.pid"
  echo -e "${GREEN}[+]${NC} PID: $(cat "$ABS_OUTPUT/scan.pid")"
  echo -e "${GREEN}[+]${NC} Acompanhe: tail -f $ABS_OUTPUT/nohup.log"
  exit 0
fi

# ---------- Logging ----------
log() { echo -e "$1" | tee -a "$SCAN_LOG"; }

# ---------- Início ----------
banner
log ""
log "${CYAN}[*]${NC} Início: $(date)"
log "${CYAN}[*]${NC} Hosts: $ARQUIVO_HOSTS"
log "${CYAN}[*]${NC} Saída: $OUTPUT_DIR"
log "${CYAN}[*]${NC} Portas: $PORTS | Rate: $RATE | Severidades: $SEVERITY"
log ""

# ---------- Pré-checks: libpcap + gateway ----------
log "${CYAN}[0/3]${NC} Verificando dependências e rede..."
check_fix_libpcap
resolve_masscan_router_args
log ""

# ---------- Masscan ----------
log "${CYAN}[1/3]${NC} Executando Masscan..."
masscan -iL "$ARQUIVO_HOSTS" -p "$PORTS" --rate="$RATE" $MASSCAN_ROUTER_ARGS -oL "$MASSCAN_LOG" 2>&1 \
  | grep -v "^$" | while IFS= read -r line; do log "    ${line}"; done
MASSCAN_STATUS=${PIPESTATUS[0]}

if [ $MASSCAN_STATUS -ne 0 ] || [ ! -s "$MASSCAN_LOG" ]; then
  log "${YELLOW}[!]${NC} Masscan não retornou resultados ou falhou."
  TOTAL_HOSTS=0
else
  grep -E "^open" "$MASSCAN_LOG" | awk '{print $4":"$3}' | sort -u > "$NUCLEI_INPUT"
  TOTAL_HOSTS=$(wc -l < "$NUCLEI_INPUT")
  log "${GREEN}[+]${NC} Hosts/portas abertas encontradas: $TOTAL_HOSTS"
fi

# ---------- Nuclei ----------
if [ "$TOTAL_HOSTS" -eq 0 ]; then
  log "${YELLOW}[!]${NC} Nenhum alvo para o Nuclei. Encerrando."
  touch "$NUCLEI_TXT"
else
  log "${CYAN}[2/3]${NC} Executando Nuclei em $TOTAL_HOSTS alvos..."
  nuclei \
    -l "$NUCLEI_INPUT" \
    -s "$SEVERITY" \
    -silent \
    -nc \
    -c "$CONCURRENCY" \
    -rl 1000 \
    -sa \
    -json-export "$NUCLEI_JSON" \
    $(if $SAVE_TXT; then echo "-o $NUCLEI_TXT"; fi) \
    > /dev/null 2>&1

  TOTAL_VULNS=0
  [ -f "$NUCLEI_TXT" ] && TOTAL_VULNS=$(wc -l < "$NUCLEI_TXT")
  log "${GREEN}[+]${NC} Vulnerabilidades encontradas: $TOTAL_VULNS"
fi

# ---------- Resumo final ----------
log ""
log "${BOLD}========== RESUMO ==========${NC}"
log "${CYAN}Diretório de saída:${NC}  $OUTPUT_DIR"
[ -f "$MASSCAN_LOG" ]  && log "${CYAN}Masscan log:${NC}        $MASSCAN_LOG"
[ -f "$NUCLEI_INPUT" ] && log "${CYAN}Alvos Nuclei:${NC}       $NUCLEI_INPUT  (${TOTAL_HOSTS} hosts)"
$SAVE_TXT && [ -f "$NUCLEI_TXT" ] && log "${CYAN}Resultados TXT:${NC}     $NUCLEI_TXT"
[ -f "$NUCLEI_JSON" ]  && log "${CYAN}Resultados JSON:${NC}    $NUCLEI_JSON"
log "${CYAN}Scan log:${NC}           $SCAN_LOG"
log "${CYAN}Fim:${NC}                $(date)"
log "${BOLD}============================${NC}"
