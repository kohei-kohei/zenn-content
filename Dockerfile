FROM node:20-bookworm-slim

WORKDIR /home/zenn-content

COPY node_modules/ package.json package-lock.json ./

RUN npm install
