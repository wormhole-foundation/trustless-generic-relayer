FROM --platform=linux/amd64 node:lts-alpine as builder

# Create app directory
WORKDIR /usr/src/app

# COPY package.json package-lock.json /src/

# ENV NODE_ENV=production
# RUN npm ci

# Install app dependencies
# COPY . /src

COPY . .

CMD [ "npm", "run", "k8s-testnet" ]