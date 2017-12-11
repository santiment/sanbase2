FROM node:latest

RUN mkdir /usr/app
WORKDIR /usr/app

COPY package.json /usr/app/package.json
RUN yarn

COPY . /usr/app

# Build production and optimized app
RUN npm run build

EXPOSE 9000

# defined in package.json
CMD [ "npm", "run", "start:server" ]
