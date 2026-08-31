openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/tls.key -out /tmp/tls.crt \
  -subj "/CN=cluster-project.local/O=ESGI" \
  -addext "subjectAltName=DNS:cluster-project.local"


kubectl create secret tls cluster-project-tls \
  --cert=/tmp/tls.crt --key=/tmp/tls.key \
  -n cluster-project \
  --dry-run=client -o yaml > kubernetes/12-tls-secret.yaml

kubectl apply -f kubernetes/12-tls-secret.yaml