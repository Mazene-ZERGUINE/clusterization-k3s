## Replace with your docker hub account informations 

#!/usr/bin/env bash
set -euo pipefail

REGISTRY_USER="mazene"
PREFIX="cluster-project"
VERSION="${1:-1.0.0}"
PLATFORMS="linux/amd64,linux/arm64"

COMPONENTS=(
  "frontend:./frontend"
  "auth-service:./services/auth-service"
  "product-service:./services/product-service"
  "order-service:./services/order-service"
)

docker login
docker buildx create --use --name "$PREFIX" 2>/dev/null || docker buildx use "$PREFIX"

for entry in "${COMPONENTS[@]}"; do
  name="${entry%%:*}"
  path="${entry#*:}"
  image="${REGISTRY_USER}/${PREFIX}-${name}:${VERSION}"

  echo ""
  echo "==> building ${image} from ${path}"
  docker buildx build --platform "$PLATFORMS" -t "$image" --push "$path"
done

echo ""
echo "==> verifying"
for entry in "${COMPONENTS[@]}"; do
  name="${entry%%:*}"
  image="${REGISTRY_USER}/${PREFIX}-${name}:${VERSION}"
  echo "-- ${image}"
  docker buildx imagetools inspect "$image" | grep -E 'Platform|MediaType: application/vnd.oci.image.index' | head -5
done