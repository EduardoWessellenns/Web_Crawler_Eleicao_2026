#!/usr/bin/env bash
# resultados_tse.sh
# Consulta os resultados oficiais do TSE por cargo e município e exibe
# os candidatos mais votados em formato de tabela no terminal.
#
# Uso:
#   ./resultados_tse.sh            # usa os valores padrão
#   ./resultados_tse.sh --help     # mostra a ajuda
#
# Variáveis de ambiente (opcionais):
#   TSE_RESULTS_UF, TSE_RESULTS_MUNICIPALITY, TSE_RESULTS_YEAR,
#   TSE_RESULTS_LIMIT, TSE_RESULTS_COLOR (auto|always|never), entre outras.
set -Eeuo pipefail

readonly DEFAULT_BASE_URL="https://resultados.tse.jus.br/oficial"
readonly -a CARGOS=(6 7 5 3 1)

BASE_URL="${TSE_RESULTS_BASE_URL:-$DEFAULT_BASE_URL}"
YEAR="${TSE_RESULTS_YEAR:-2026}"
UF="${TSE_RESULTS_UF:-ma}"
MUNICIPIO="${TSE_RESULTS_MUNICIPALITY:-07242}"
LIMIT="${TSE_RESULTS_LIMIT:-10}"
FEDERAL_ELECTION="${TSE_RESULTS_FEDERAL_ELECTION:-6257}"
STATE_ELECTION="${TSE_RESULTS_STATE_ELECTION:-6259}"
COLOR_MODE="${TSE_RESULTS_COLOR:-auto}"

usage() {
  cat <<EOF
Uso: ${0##*/} [-h|--help]

Exibe os candidatos mais votados por cargo para um município.

Variáveis de ambiente (valor atual entre parênteses):
  TSE_RESULTS_UF            sigla do estado ($UF)
  TSE_RESULTS_MUNICIPALITY  código do município, 5 dígitos ($MUNICIPIO)
  TSE_RESULTS_YEAR          ano da eleição ($YEAR)
  TSE_RESULTS_LIMIT         máximo de candidatos por cargo ($LIMIT)
  TSE_RESULTS_COLOR         auto, always ou never ($COLOR_MODE)
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) printf 'Opção desconhecida: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
esac

die() { printf 'Erro: %s\n' "$*" >&2; exit 1; }
command -v curl >/dev/null || die "curl não encontrado"
command -v jq >/dev/null || die "jq não encontrado"
[[ "$UF" =~ ^[[:alpha:]]{2}$ ]] || die "TSE_RESULTS_UF deve conter duas letras"
[[ "$MUNICIPIO" =~ ^[0-9]{5}$ ]] || die "TSE_RESULTS_MUNICIPALITY deve conter cinco dígitos"
[[ "$YEAR" =~ ^[0-9]{4}$ ]] || die "TSE_RESULTS_YEAR deve conter quatro dígitos"
[[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || die "TSE_RESULTS_LIMIT deve ser um inteiro positivo"
[[ "$FEDERAL_ELECTION" =~ ^[0-9]+$ && "$STATE_ELECTION" =~ ^[0-9]+$ ]] || die "códigos de eleição devem ser numéricos"
[[ "$COLOR_MODE" =~ ^(auto|always|never)$ ]] || die "TSE_RESULTS_COLOR deve ser auto, always ou never"

UF="${UF,,}"
BASE_URL="${BASE_URL%/}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

use_color=false
if [[ "$COLOR_MODE" == always ]] || { [[ "$COLOR_MODE" == auto && -t 1 && "${TERM:-dumb}" != dumb ]] && [[ ! -v NO_COLOR ]]; }; then
  use_color=true
fi

print_rule() {
  local pos_width="$1" name_width="$2" number_width="$3" votes_width="$4"
  printf '+-%*s-+-%*s-+-%*s-+-%*s-+\n' "$pos_width" '' "$name_width" '' "$number_width" '' "$votes_width" '' | tr ' ' '-'
}

print_table() {
  local -n table_rows="$1"
  local pos_width=${#pos_header} name_width=${#name_header} number_width=${#number_header} votes_width=${#votes_header}
  local row pos name number votes

  for row in "${table_rows[@]}"; do
    IFS=$'\t' read -r pos name number votes <<<"$row"
    (( ${#pos} > pos_width )) && pos_width=${#pos}
    (( ${#name} > name_width )) && name_width=${#name}
    (( ${#number} > number_width )) && number_width=${#number}
    (( ${#votes} > votes_width )) && votes_width=${#votes}
  done

  print_rule "$pos_width" "$name_width" "$number_width" "$votes_width"
  printf '| %*s | %-*s | %*s | %*s |\n' "$pos_width" "$pos_header" "$name_width" "$name_header" "$number_width" "$number_header" "$votes_width" "$votes_header"
  print_rule "$pos_width" "$name_width" "$number_width" "$votes_width"
  for row in "${table_rows[@]}"; do
    IFS=$'\t' read -r pos name number votes <<<"$row"
    if $use_color; then
      printf '| %*s | \033[36m%-*s\033[0m | %*s | \033[32m%*s\033[0m |\n' "$pos_width" "$pos" "$name_width" "$name" "$number_width" "$number" "$votes_width" "$votes"
    else
      printf '| %*s | %-*s | %*s | %*s |\n' "$pos_width" "$pos" "$name_width" "$name" "$number_width" "$number" "$votes_width" "$votes"
    fi
  done
  print_rule "$pos_width" "$name_width" "$number_width" "$votes_width"
}

readonly pos_header="POS" name_header="NOME" number_header="NÚMERO" votes_header="VOTOS"

election_for_cargo() {
  case "$1" in
    1) printf '%s' "$FEDERAL_ELECTION" ;;
    3|5|6|7) printf '%s' "$STATE_ELECTION" ;;
    *) die "cargo não suportado: $1" ;;
  esac
}

for cargo in "${CARGOS[@]}"; do
  election="$(election_for_cargo "$cargo")"
  file="$tmp_dir/cargo-$cargo.json"
  printf -v cargo_padded '%04d' "$cargo"
  printf -v election_padded '%06d' "$election"
  url="$BASE_URL/ele$YEAR/$election/dados/$UF/${UF}${MUNICIPIO}-c${cargo_padded}-e${election_padded}-u.json"

  curl --fail --silent --show-error --location \
    --retry 3 --retry-all-errors --connect-timeout 10 --max-time 30 \
    --output "$file" "$url" || die "falha ao consultar o cargo $cargo"
  jq -e '.carg | type == "array"' "$file" >/dev/null || die "resposta inválida para o cargo $cargo"

  cargo_name="$(jq -r --arg cargo "$cargo" '.carg[] | select(.cd == $cargo) | .nmn' "$file" | head -n 1)"
  [[ -n "$cargo_name" ]] || die "cargo $cargo ausente na resposta"
  printf '\n%s (cargo %s)\n' "$cargo_name" "$cargo"
  rows_file="$tmp_dir/cargo-$cargo.tsv"
  jq -r --arg cargo "$cargo" --argjson limit "$LIMIT" '
    [
      .carg[] | select(.cd == $cargo)
      | .. | objects | .cand? // empty | .[]
      | select((.nmu // "") != "" and (.n // "") != "")
      | { nome: (.nmu | gsub("[[:cntrl:]]"; " ")), numero: .n, votos: ((.vap // "0") | tonumber) }
    ]
    | unique_by(.numero)
    | sort_by([-.votos, (.nome | ascii_downcase), .numero])
    | .[:$limit]
    | to_entries[]
    | [(.key + 1 | tostring), .value.nome, .value.numero, (.value.votos | tostring)] | @tsv
  ' "$file" >"$rows_file"
  mapfile -t rows <"$rows_file"
  print_table rows
done
