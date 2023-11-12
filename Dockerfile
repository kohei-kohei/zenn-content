FROM node:20-bookworm-slim

WORKDIR /home/zenn-content

COPY package.json package-lock.json ./

RUN npm install
