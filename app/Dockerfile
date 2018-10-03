FROM node:8.9.0-alpine

RUN mkdir /usr/app
WORKDIR /usr/app

COPY . /usr/app
RUN npm install -g yarn
RUN yarn
