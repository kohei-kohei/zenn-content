FROM node:22.14.0-bookworm-slim

WORKDIR /home/zenn-content

COPY package.json package-lock.json ./

RUN npm install
