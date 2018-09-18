FROM node:8.11.3

RUN mkdir /usr/app
WORKDIR /usr/app

COPY . /usr/app
RUN npm install -g yarn
RUN yarn
