bash deploy-redis.sh
kubectl apply -f ./spy-service.yaml
source ../../pkeys.sh
bash inject-private-keys.sh
kubectl apply -f ./simple-gr.yaml
