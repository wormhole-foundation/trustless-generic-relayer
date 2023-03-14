#! /bin/sh

kubectl delete secret redis-generic-relayer --ignore-not-found --namespace generic-relayer

kubectl create secret generic redis-generic-relayer \
    --from-literal=RELAYER_ENGINE_REDIS_HOST=${RELAYER_ENGINE_REDIS_HOST} \
    --from-literal=RELAYER_ENGINE_REDIS_USERNAME=${RELAYER_ENGINE_REDIS_USERNAME} \
    --from-literal=RELAYER_ENGINE_REDIS_PASSWORD=${RELAYER_ENGINE_REDIS_PASSWORD} \
    --namespace generic-relayer

