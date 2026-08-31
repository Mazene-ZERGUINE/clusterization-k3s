#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# L'ingress applique le middleware redirect-https: viser directement HTTPS evite
# un aller-retour 301 par requete.
API_URL="${PRODUCT_API_URL:-https://cluster-project.local/api}"
TLS_SECRET="${REPO_ROOT}/kubernetes/12-tls-secret.yaml"

if ! command -v node >/dev/null 2>&1; then
  echo "[ERROR] Node.js 18+ est requis pour executer ce script." >&2
  exit 1
fi

# Le certificat de l'ingress est auto-signe: sans ce CA, fetch() echoue avec
# "self-signed certificate" et la boucle de retry tourne dans le vide.
if [[ "${API_URL}" == https://* && "${PRODUCT_API_INSECURE_TLS:-0}" != "1" ]]; then
  if [[ -f "${TLS_SECRET}" ]]; then
    CA_FILE="$(mktemp -t cluster-project-ca)"
    trap 'rm -f "${CA_FILE}"' EXIT
    grep -m1 'tls.crt:' "${TLS_SECRET}" | sed 's/.*tls\.crt: *//' | base64 --decode > "${CA_FILE}"
    export NODE_EXTRA_CA_CERTS="${CA_FILE}"
  else
    echo "[WARN] ${TLS_SECRET} introuvable: la verification TLS va probablement echouer." >&2
    echo "[WARN] Relancer avec PRODUCT_API_INSECURE_TLS=1 pour ignorer le certificat." >&2
  fi
fi

if [[ "${PRODUCT_API_INSECURE_TLS:-0}" == "1" ]]; then
  echo "[WARN] Verification TLS desactivee (PRODUCT_API_INSECURE_TLS=1)." >&2
  export NODE_TLS_REJECT_UNAUTHORIZED=0
fi

echo "[INFO] Cible: ${API_URL}"

PRODUCT_API_URL="${API_URL}" node --input-type=module <<'NODE'
const baseUrl = process.env.PRODUCT_API_URL.replace(/\/$/, '');
const REQUEST_TIMEOUT_MS = 10000;
const MAX_ATTEMPTS = 30;

const products = [
  { name: 'Smartphone Galaxy S21', price: 899, description: 'Dernier smartphone Samsung avec appareil photo 108MP', stock: 15 },
  { name: 'MacBook Pro M1', price: 1299, description: 'Ordinateur portable Apple avec puce M1', stock: 10 },
  { name: 'PS5', price: 499, description: 'Console de jeu derniere generation', stock: 5 },
  { name: 'Ecouteurs AirPods Pro', price: 249, description: 'Ecouteurs sans fil avec reduction de bruit', stock: 20 },
  { name: 'Nintendo Switch', price: 299, description: 'Console de jeu portable', stock: 12 },
  { name: 'iPad Air', price: 599, description: 'Tablette Apple avec ecran Retina', stock: 8 },
  { name: 'Montre connectee', price: 199, description: "Montre intelligente avec suivi d'activite", stock: 25 },
  { name: 'Enceinte Bluetooth', price: 79, description: 'Enceinte portable waterproof', stock: 30 },
];

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Sans signal d'annulation, une connexion qui ne repond jamais bloque le script
// indefiniment au lieu de passer a la tentative suivante.
async function request(path, init = {}) {
  return fetch(`${baseUrl}${path}`, { ...init, signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS) });
}

function describe(error) {
  return error?.cause?.message ?? error?.cause?.code ?? error?.message ?? String(error);
}

// /api/health n'est pas route par l'ingress (il tombe sur le frontend et renvoie
// 404): /api/products est le seul vrai signal de disponibilite.
async function waitForProductService() {
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    try {
      const response = await request('/products');
      if (response.ok) return;
      console.log(`[WAIT ${attempt}/${MAX_ATTEMPTS}] HTTP ${response.status} sur ${baseUrl}/products`);
    } catch (error) {
      console.log(`[WAIT ${attempt}/${MAX_ATTEMPTS}] ${describe(error)}`);
    }
    await sleep(2000);
  }
  throw new Error(`product-service indisponible sur ${baseUrl}`);
}

async function getProducts() {
  const response = await request('/products');
  if (!response.ok) {
    throw new Error(`Impossible de lire les produits: HTTP ${response.status}`);
  }
  return response.json();
}

async function createProduct(product) {
  const response = await request('/products', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(product),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Creation echouee pour ${product.name}: HTTP ${response.status} ${body}`);
  }
}

await waitForProductService();
const existing = await getProducts();
const existingNames = new Set(existing.map(product => product.name));

for (const product of products) {
  if (existingNames.has(product.name)) {
    console.log(`[SKIP] ${product.name}`);
    continue;
  }
  await createProduct(product);
  console.log(`[OK] ${product.name}`);
}

console.log('Initialisation des produits terminee.');
NODE
