FROM node:20-alpine
WORKDIR /app
COPY src/package.json .
RUN apk add --no-cache nodejs
COPY src/ .
EXPOSE 3000
USER node
CMD ["node", "index.js"]
