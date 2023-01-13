
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install --set auth.enabled=false --set architecture=standalone  redis bitnami/redis
